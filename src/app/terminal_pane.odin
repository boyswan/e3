package app

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import vt "../terminal"
import posix "core:sys/posix"

when ODIN_OS == .Linux || ODIN_OS == .Darwin {
	foreign import libutil "system:util"
} else {
	foreign import libutil "system:c"
}

foreign libutil {
	forkpty :: proc(amaster: ^c.int, name: cstring, termp: rawptr, winp: ^Pty_Winsize) -> c.int ---
}

foreign import libc "system:c"

foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
}

when ODIN_OS == .Darwin {
	TIOCSWINSZ :: c.ulong(0x80087467)
} else {
	TIOCSWINSZ :: c.ulong(0x5414)
}

Pty_Winsize :: struct {
	row:    u16,
	col:    u16,
	xpixel: u16,
	ypixel: u16,
}

MAX_SCROLLBACK_LINES :: 5000

terminal_spawn_shell :: proc(term: ^Terminal_Handle, width: int, height: int) -> bool {
	if term.active {
		terminal_resize_grid(term, width, height)
		return true
	}

	if width <= 0 || height <= 0 {
		return false
	}

	winsize := Pty_Winsize {
		row = u16(height),
		col = u16(width),
	}

	configured_shell: cstring
	if len(term.shell_command) > 0 {
		configured_shell = strings.clone_to_cstring(term.shell_command)
	}

	master: c.int
	pid := forkpty(&master, nil, nil, &winsize)
	if pid < 0 {
		if configured_shell != nil {
			delete(configured_shell)
		}
		if !term.spawn_error_logged {
			fmt.eprintln("e3: failed to spawn shell with forkpty")
			term.spawn_error_logged = true
		}
		return false
	}

	if pid == 0 {
		_ = posix.setenv("TERM", "xterm-256color", true)
		_ = posix.setenv("COLORTERM", "truecolor", true)

		shell := configured_shell
		if shell == nil {
			shell = posix.getenv("SHELL")
		}
		if shell == nil {
			if account := posix.getpwuid(posix.getuid()); account != nil {
				shell = account.pw_shell
			}
		}
		if shell == nil {
			shell = "/bin/sh"
		}

		argv := [?]cstring{shell, nil}
		posix.execvp(argv[0], raw_data(argv[:]))
		fmt.eprintln("e3: failed to execute shell:", string(shell))
		posix._exit(127)
	}

	if configured_shell != nil {
		delete(configured_shell)
	}
	term.active = true
	term.spawn_error_logged = false
	term.pty_fd = int(master)
	term.pid = int(pid)
	terminal_resize_grid(term, width, height)
	return true
}

terminal_resize_grid :: proc(term: ^Terminal_Handle, width: int, height: int) {
	if width <= 0 || height <= 0 {
		return
	}

	if term.backend == .Ghostty {
		terminal_resize_ghostty(term, width, height)
		return
	}

	if term.width == width && term.height == height && term.cells != nil {
		return
	}

	if term.cells != nil {
		delete(term.cells)
	}

	term.width = width
	term.height = height
	term.cursor_x = 0
	term.cursor_y = 0
	terminal_reset_escape(term)
	term.cells = make([]byte, width * height)
	terminal_clear_grid(term)

	terminal_resize_pty(term, width, height)
}

terminal_resize_ghostty :: proc(term: ^Terminal_Handle, width: int, height: int) {
	if term.ghostty == nil {
		options := vt.GhosttyTerminalOptions {
			cols = u16(width),
			rows = u16(height),
			max_scrollback = MAX_SCROLLBACK_LINES,
		}
		if vt.ghostty_terminal_new(nil, &term.ghostty, options) != .SUCCESS {
			return
		}

		vt.ghostty_terminal_set(term.ghostty, .USERDATA, rawptr(term))
		write_pty: vt.GhosttyTerminalWritePtyFn = terminal_ghostty_write_pty
		vt.ghostty_terminal_set(term.ghostty, .WRITE_PTY, transmute(rawptr)write_pty)

		vt.ghostty_render_state_new(nil, &term.render_state)
		vt.ghostty_render_state_row_iterator_new(nil, &term.row_iterator)
		vt.ghostty_render_state_row_cells_new(nil, &term.row_cells)
	} else if term.width != width || term.height != height {
		vt.ghostty_terminal_resize(term.ghostty, u16(width), u16(height), 1, 1)
	}

	term.width = width
	term.height = height
	terminal_resize_pty(term, width, height)
}

terminal_resize_pty :: proc(term: ^Terminal_Handle, width: int, height: int) {
	if term.active {
		winsize := Pty_Winsize {
			row = u16(height),
			col = u16(width),
		}
		ioctl(c.int(term.pty_fd), TIOCSWINSZ, &winsize)
	}
}

terminal_clear_grid :: proc(term: ^Terminal_Handle) {
	for index in 0 ..< len(term.cells) {
		term.cells[index] = ' '
	}
}

terminal_destroy :: proc(term: ^Terminal_Handle) {
	if term.active {
		posix.close(posix.FD(term.pty_fd))
	}
	if term.cells != nil {
		delete(term.cells)
	}
	if len(term.title_cache) > 0 {
		delete(term.title_cache)
	}
	if term.row_cells != nil {
		vt.ghostty_render_state_row_cells_free(term.row_cells)
	}
	if term.row_iterator != nil {
		vt.ghostty_render_state_row_iterator_free(term.row_iterator)
	}
	if term.render_state != nil {
		vt.ghostty_render_state_free(term.render_state)
	}
	if term.ghostty != nil {
		vt.ghostty_terminal_free(term.ghostty)
	}
	term^ = Terminal_Handle{}
}

terminal_poll_read :: proc(term: ^Terminal_Handle) -> bool {
	if !term.active {
		return false
	}

	poll_fd := posix.pollfd {
		fd = posix.FD(term.pty_fd),
		events = {.IN},
	}

	changed := false
	for posix.poll(&poll_fd, 1, 0) > 0 {
		buffer: [4096]byte
		count := posix.read(posix.FD(term.pty_fd), raw_data(buffer[:]), c.size_t(len(buffer)))
		if count <= 0 {
			break
		}

		terminal_write_output(term, buffer[:count])
		changed = true
	}

	return changed
}

terminal_write_input :: proc(term: ^Terminal_Handle, data: []byte) -> bool {
	if !term.active || len(data) == 0 {
		return false
	}

	total_written := 0
	for total_written < len(data) {
		remaining := data[total_written:]
		written := posix.write(
			posix.FD(term.pty_fd),
			raw_data(remaining),
			c.size_t(len(remaining)),
		)
		if written <= 0 {
			break
		}
		total_written += int(written)
	}

	return total_written > 0
}

terminal_write_output :: proc(term: ^Terminal_Handle, data: []byte) {
	if term.backend == .Ghostty {
		terminal_write_ghostty_output(term, data)
		return
	}

	for byte_value in data {
		terminal_put_output_byte(term, byte_value)
	}
}

terminal_write_ghostty_output :: proc(term: ^Terminal_Handle, data: []byte) {
	if term.ghostty == nil || len(data) == 0 {
		return
	}

	vt.ghostty_terminal_vt_write(term.ghostty, raw_data(data), c.size_t(len(data)))

	// Keep the viewport pinned to the bottom on new output.
	vt.ghostty_terminal_scroll_viewport(term.ghostty, vt.GhosttyTerminalScrollViewport{tag = .BOTTOM})
}

terminal_ghostty_write_pty :: proc "c" (_: vt.GhosttyTerminal, userdata: rawptr, data: [^]u8, len: c.size_t) {
	term := (^Terminal_Handle)(userdata)
	if term == nil || !term.active || data == nil || len == 0 {
		return
	}

	total_written := 0
	for total_written < int(len) {
		written := posix.write(
			posix.FD(term.pty_fd),
			&data[total_written],
			c.size_t(int(len) - total_written),
		)
		if written <= 0 {
			break
		}
		total_written += int(written)
	}
}

terminal_put_output_byte :: proc(term: ^Terminal_Handle, value: byte) {
	if term.escape != 0 {
		terminal_handle_escape_byte(term, value)
		return
	}

	switch value {
	case 0x1b:
		term.escape = 1
	case '\r':
		term.cursor_x = 0
	case '\n':
		terminal_newline(term)
	case '\b', 0x7f:
		if term.cursor_x > 0 {
			term.cursor_x -= 1
		}
	case '\t':
		next_tab := ((term.cursor_x / 8) + 1) * 8
		for term.cursor_x < next_tab {
			terminal_put_printable(term, ' ')
		}
	case 0 ..= 31:
		// Ignore other control bytes for this first terminal slice.
	case:
		terminal_put_printable(term, value)
	}
}

terminal_handle_escape_byte :: proc(term: ^Terminal_Handle, value: byte) {
	switch term.escape {
	case 1:
		if value == '[' {
			terminal_begin_csi(term)
			return
		}
		if value == ']' {
			term.escape = 3
			return
		}

		// A few single-byte ESC sequences seen from shells/editors.
		switch value {
		case 'c':
			terminal_clear_grid(term)
			term.cursor_x = 0
			term.cursor_y = 0
		case 'D':
			terminal_newline(term)
		case 'E':
			terminal_newline(term)
			term.cursor_x = 0
		case 'M':
			terminal_reverse_index(term)
		case '7', '8':
			// Save/restore cursor are ignored for now.
		}
		terminal_reset_escape(term)
	case 2:
		terminal_handle_csi_byte(term, value)
	case 3:
		if value == 0x07 {
			terminal_reset_escape(term)
			return
		}
		if value == 0x1b {
			term.escape = 4
		}
	case 4:
		if value == '\\' {
			terminal_reset_escape(term)
		} else {
			term.escape = 3
		}
	}
}

terminal_begin_csi :: proc(term: ^Terminal_Handle) {
	term.escape = 2
	term.escape_param_count = 0
	term.escape_value = 0
	term.escape_has_value = false
	term.escape_private = false
}

terminal_reset_escape :: proc(term: ^Terminal_Handle) {
	term.escape = 0
	term.escape_param_count = 0
	term.escape_value = 0
	term.escape_has_value = false
	term.escape_private = false
}

terminal_handle_csi_byte :: proc(term: ^Terminal_Handle, value: byte) {
	if value >= '0' && value <= '9' {
		term.escape_value = term.escape_value * 10 + int(value - '0')
		term.escape_has_value = true
		return
	}

	if value == ';' || value == ':' {
		terminal_commit_csi_param(term)
		return
	}

	if value == '?' {
		term.escape_private = true
		return
	}

	// Ignore intermediate bytes until the final byte.
	if value >= 0x20 && value <= 0x2f {
		return
	}

	if value >= 0x40 && value <= 0x7e {
		if term.escape_has_value {
			terminal_commit_csi_param(term)
		}
		terminal_apply_csi(term, value)
		terminal_reset_escape(term)
		return
	}

	terminal_reset_escape(term)
}

terminal_commit_csi_param :: proc(term: ^Terminal_Handle) {
	if term.escape_param_count >= len(term.escape_params) {
		term.escape_value = 0
		term.escape_has_value = false
		return
	}

	if term.escape_has_value {
		term.escape_params[term.escape_param_count] = term.escape_value
	} else {
		term.escape_params[term.escape_param_count] = 0
	}
	term.escape_param_count += 1
	term.escape_value = 0
	term.escape_has_value = false
}

terminal_apply_csi :: proc(term: ^Terminal_Handle, final: byte) {
	switch final {
	case 'A':
		terminal_move_cursor(term, 0, -terminal_csi_param(term, 0, 1))
	case 'B':
		terminal_move_cursor(term, 0, terminal_csi_param(term, 0, 1))
	case 'C':
		terminal_move_cursor(term, terminal_csi_param(term, 0, 1), 0)
	case 'D':
		terminal_move_cursor(term, -terminal_csi_param(term, 0, 1), 0)
	case 'E':
		terminal_move_cursor(term, 0, terminal_csi_param(term, 0, 1))
		term.cursor_x = 0
	case 'F':
		terminal_move_cursor(term, 0, -terminal_csi_param(term, 0, 1))
		term.cursor_x = 0
	case 'G':
		term.cursor_x = terminal_csi_param(term, 0, 1) - 1
		terminal_clamp_cursor(term)
	case 'H', 'f':
		term.cursor_y = terminal_csi_param(term, 0, 1) - 1
		term.cursor_x = terminal_csi_param(term, 1, 1) - 1
		terminal_clamp_cursor(term)
	case 'J':
		terminal_clear_screen_mode(term, terminal_csi_param(term, 0, 0))
	case 'K':
		terminal_clear_line_mode(term, terminal_csi_param(term, 0, 0))
	case 'm':
		// SGR color/style is intentionally ignored in this stepping-stone terminal.
	case 'h', 'l':
		// Mode set/reset, including bracketed paste (?2004h/l) and cursor visibility.
	case 'r':
		// Scroll region ignored for now.
	}
}

terminal_csi_param :: proc(term: ^Terminal_Handle, index: int, default_value: int) -> int {
	if index < 0 || index >= term.escape_param_count {
		return default_value
	}

	value := term.escape_params[index]
	if value == 0 {
		return default_value
	}

	return value
}

terminal_move_cursor :: proc(term: ^Terminal_Handle, dx: int, dy: int) {
	term.cursor_x += dx
	term.cursor_y += dy
	terminal_clamp_cursor(term)
}

terminal_clamp_cursor :: proc(term: ^Terminal_Handle) {
	if term.width <= 0 || term.height <= 0 {
		term.cursor_x = 0
		term.cursor_y = 0
		return
	}

	if term.cursor_x < 0 {
		term.cursor_x = 0
	}
	if term.cursor_y < 0 {
		term.cursor_y = 0
	}
	if term.cursor_x >= term.width {
		term.cursor_x = term.width - 1
	}
	if term.cursor_y >= term.height {
		term.cursor_y = term.height - 1
	}
}

terminal_clear_screen_mode :: proc(term: ^Terminal_Handle, mode: int) {
	if term.cells == nil || term.width <= 0 || term.height <= 0 {
		return
	}

	switch mode {
	case 0:
		terminal_clear_range(term, term.cursor_x, term.cursor_y, term.width - 1, term.height - 1)
	case 1:
		terminal_clear_range(term, 0, 0, term.cursor_x, term.cursor_y)
	case 2, 3:
		terminal_clear_grid(term)
	}
}

terminal_clear_line_mode :: proc(term: ^Terminal_Handle, mode: int) {
	if term.cells == nil || term.cursor_y < 0 || term.cursor_y >= term.height {
		return
	}

	switch mode {
	case 0:
		terminal_clear_range(term, term.cursor_x, term.cursor_y, term.width - 1, term.cursor_y)
	case 1:
		terminal_clear_range(term, 0, term.cursor_y, term.cursor_x, term.cursor_y)
	case 2:
		terminal_clear_range(term, 0, term.cursor_y, term.width - 1, term.cursor_y)
	}
}

terminal_clear_range :: proc(term: ^Terminal_Handle, left: int, top: int, right: int, bottom: int) {
	if term.cells == nil || term.width <= 0 || term.height <= 0 {
		return
	}

	clamped_left := left
	clamped_top := top
	clamped_right := right
	clamped_bottom := bottom
	if clamped_left < 0 {
		clamped_left = 0
	}
	if clamped_top < 0 {
		clamped_top = 0
	}
	if clamped_right >= term.width {
		clamped_right = term.width - 1
	}
	if clamped_bottom >= term.height {
		clamped_bottom = term.height - 1
	}
	if clamped_left > clamped_right || clamped_top > clamped_bottom {
		return
	}

	for y in clamped_top ..= clamped_bottom {
		start_x := clamped_left
		end_x := clamped_right
		if y == clamped_top {
			start_x = clamped_left
		} else {
			start_x = 0
		}
		if y == clamped_bottom {
			end_x = clamped_right
		} else {
			end_x = term.width - 1
		}

		for x in start_x ..= end_x {
			term.cells[y * term.width + x] = ' '
		}
	}
}

terminal_reverse_index :: proc(term: ^Terminal_Handle) {
	term.cursor_y -= 1
	if term.cursor_y >= 0 {
		return
	}

	term.cursor_y = 0
	terminal_scroll_down(term)
}

terminal_scroll_down :: proc(term: ^Terminal_Handle) {
	if term.width <= 0 || term.height <= 0 {
		return
	}

	for y := term.height - 1; y > 0; y -= 1 {
		for x in 0 ..< term.width {
			term.cells[y * term.width + x] = term.cells[(y - 1) * term.width + x]
		}
	}

	for x in 0 ..< term.width {
		term.cells[x] = ' '
	}
}

terminal_put_printable :: proc(term: ^Terminal_Handle, value: byte) {
	if term.width <= 0 || term.height <= 0 || term.cells == nil {
		return
	}

	if term.cursor_x >= term.width {
		terminal_newline(term)
	}

	index := term.cursor_y * term.width + term.cursor_x
	if index >= 0 && index < len(term.cells) {
		term.cells[index] = value
	}

	term.cursor_x += 1
}

terminal_newline :: proc(term: ^Terminal_Handle) {
	term.cursor_x = 0
	term.cursor_y += 1
	if term.cursor_y >= term.height {
		terminal_scroll_up(term)
		term.cursor_y = term.height - 1
	}
}

terminal_scroll_up :: proc(term: ^Terminal_Handle) {
	if term.width <= 0 || term.height <= 0 {
		return
	}

	for y in 1 ..< term.height {
		for x in 0 ..< term.width {
			term.cells[(y - 1) * term.width + x] = term.cells[y * term.width + x]
		}
	}

	last_row := term.height - 1
	for x in 0 ..< term.width {
		term.cells[last_row * term.width + x] = ' '
	}
}

sync_pane_terminals :: proc(node: ^Node, inset := 1, extra_width_padding := 0, extra_height_padding := 0) {
	if node == nil {
		return
	}

	terminal_width_padding := inset * 2 + extra_width_padding
	terminal_height_padding := inset * 2 + extra_height_padding
	switch node.kind {
	case .Pane:
		if node.pane != nil {
			bounds := node.pane.bounds
			terminal_spawn_shell(
				&node.pane.terminal,
				terminal_max_int(bounds.width - terminal_width_padding, 1),
				terminal_max_int(bounds.height - terminal_height_padding, 1),
			)
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			sync_pane_terminals(child, inset, extra_width_padding, extra_height_padding)
		}
	case .Stacked, .Tabbed:
		for child in node.children {
			sync_pane_terminals(child, inset, extra_width_padding, extra_height_padding)
		}
	}
}

PANE_TITLE_REFRESH_INTERVAL :: 150 * time.Millisecond

// Rendering reads cached title state, as i3's decoration renderer reads the
// cached i3Window name. Title discovery and change detection happen while the
// pane is polled, not while its decoration is drawn.
pane_title :: proc(pane: ^Pane) -> string {
	if pane == nil {
		return ""
	}
	if len(pane.terminal.title_cache) > 0 {
		return pane.terminal.title_cache
	}
	return "~"
}

refresh_pane_title :: proc(pane: ^Pane) -> bool {
	if pane == nil || !pane.terminal.active {
		return false
	}

	term := &pane.terminal
	if term.title_initialized && time.tick_since(term.title_refresh_tick) < PANE_TITLE_REFRESH_INTERVAL {
		return false
	}

	// i3 treats _NET_WM_NAME as the authoritative UTF-8 client title and only
	// uses WM_NAME while no _NET_WM_NAME has been seen. OSC 0/2 is the terminal
	// equivalent of that client title. Our native cwd/process title is the
	// no-configuration fallback for panes whose client has never set a title.
	title := pane_osc_title(term)
	if len(title) > 0 {
		term.title_uses_client_value = true
	} else if term.title_uses_client_value {
		// Match i3's empty-property behavior: keep the last authoritative title
		// instead of replacing it with a fallback.
		title = term.title_cache
	} else {
		title = native_terminal_title(term)
		if len(title) == 0 {
			title = "~"
		}
	}

	changed := title != term.title_cache
	if changed {
		if len(term.title_cache) > 0 {
			delete(term.title_cache)
		}
		term.title_cache = strings.clone(title)
	}
	term.title_refresh_tick = time.tick_now()
	term.title_initialized = true
	return changed
}

pane_osc_title :: proc(term: ^Terminal_Handle) -> string {
	if term == nil || term.backend != .Ghostty || term.ghostty == nil {
		return ""
	}

	title: vt.GhosttyString
	if vt.ghostty_terminal_get(term.ghostty, .TITLE, &title) != .SUCCESS || title.ptr == nil || title.len == 0 {
		return ""
	}

	// i3 truncates X11 title properties at the first zero byte.
	value := string(title.ptr[:int(title.len)])
	if zero_index := strings.index_byte(value, 0); zero_index >= 0 {
		value = value[:zero_index]
	}
	return value
}

poll_pane_terminals :: proc(node: ^Node) -> bool {
	if node == nil {
		return false
	}

	changed := false
	switch node.kind {
	case .Pane:
		if node.pane != nil {
			changed = terminal_poll_read(&node.pane.terminal)
			changed = refresh_pane_title(node.pane) || changed
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			changed = poll_pane_terminals(child) || changed
		}
	case .Stacked, .Tabbed:
		for child in node.children {
			changed = poll_pane_terminals(child) || changed
		}
	}

	return changed
}

poll_all_terminals :: proc(app: ^App) -> bool {
	changed := false
	for index in 0 ..< len(app.workspaces) {
		changed = poll_pane_terminals(app.workspaces[index].root) || changed
	}
	return changed
}

write_focused_terminal :: proc(app: ^App, data: []byte) -> bool {
	workspace := active_workspace(app)
	if workspace == nil {
		return false
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.pane == nil {
		return false
	}

	return terminal_write_input(&focused.pane.terminal, data)
}


terminal_max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

terminal_scroll_view :: proc(term: ^Terminal_Handle, lines: int) {
	if term == nil || lines == 0 || term.ghostty == nil {
		return
	}
	behavior := vt.GhosttyTerminalScrollViewport {
		tag = .DELTA,
		value = vt.GhosttyTerminalScrollViewportValue{delta = c.ptrdiff_t(-lines)},
	}
	vt.ghostty_terminal_scroll_viewport(term.ghostty, behavior)
}

scroll_focused_terminal :: proc(app: ^App, lines: int) -> bool {
	workspace := active_workspace(app)
	if workspace == nil || workspace.root == nil || lines == 0 {
		return false
	}
	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.pane == nil {
		return false
	}
	terminal_scroll_view(&focused.pane.terminal, lines)
	return true
}
