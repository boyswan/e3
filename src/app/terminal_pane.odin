package app

import "core:c"
import vt "../terminal"
import posix "core:sys/posix"

when ODIN_OS == .Linux {
	foreign import libutil "system:util"
} else {
	foreign import libutil "system:c"
}

foreign libutil {
	forkpty :: proc(amaster: ^c.int, name: cstring, termp: rawptr, winp: ^Pty_Winsize) -> c.int ---
}

foreign import libc "system:c"

foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, argp: rawptr) -> c.int ---
}

TIOCSWINSZ :: c.ulong(0x5414)

Pty_Winsize :: struct {
	row:    u16,
	col:    u16,
	xpixel: u16,
	ypixel: u16,
}

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

	master: c.int
	pid := forkpty(&master, nil, nil, &winsize)
	if pid < 0 {
		return false
	}

	if pid == 0 {
		_ = posix.setenv("TERM", "xterm-256color", true)
		_ = posix.setenv("COLORTERM", "truecolor", true)

		shell := posix.getenv("SHELL")
		if shell == nil {
			shell = "/bin/sh"
		}

		argv := [?]cstring{shell, nil}
		posix.execvp(argv[0], raw_data(argv[:]))
		posix._exit(127)
	}

	term.active = true
	term.pty_fd = int(master)
	term.pid = int(pid)
	terminal_resize_grid(term, width, height)
	return true
}

terminal_resize_grid :: proc(term: ^Terminal_Handle, width: int, height: int) {
	if width <= 0 || height <= 0 {
		return
	}

	if term.backend == .Libvterm {
		terminal_resize_libvterm(term, width, height)
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

terminal_resize_libvterm :: proc(term: ^Terminal_Handle, width: int, height: int) {
	if term.vterm == nil {
		vt.check_version(0, 3)
		term.vterm = vt.new(c.int(height), c.int(width))
		if term.vterm == nil {
			return
		}

		vt.set_utf8(term.vterm, 1)
		term.vterm_state = vt.obtain_state(term.vterm)
		term.vterm_screen = vt.obtain_screen(term.vterm)
		if term.vterm_screen != nil {
			vt.set_damage_merge(term.vterm_screen, .Screen)
			vt.reset(term.vterm_screen, 1)
		}
	} else if term.width != width || term.height != height {
		vt.set_size(term.vterm, c.int(height), c.int(width))
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
	if term.vterm != nil {
		vt.free(term.vterm)
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

	written := posix.write(posix.FD(term.pty_fd), raw_data(data), c.size_t(len(data)))
	return written > 0
}

terminal_write_output :: proc(term: ^Terminal_Handle, data: []byte) {
	if term.backend == .Libvterm {
		terminal_write_libvterm_output(term, data)
		return
	}

	for byte_value in data {
		terminal_put_output_byte(term, byte_value)
	}
}

terminal_write_libvterm_output :: proc(term: ^Terminal_Handle, data: []byte) {
	if term.vterm == nil || len(data) == 0 {
		return
	}

	vt.input_write(term.vterm, raw_data(data), c.size_t(len(data)))
	terminal_drain_libvterm_output(term)
	if term.vterm_screen != nil {
		vt.flush_damage(term.vterm_screen)
	}
}

terminal_drain_libvterm_output :: proc(term: ^Terminal_Handle) {
	if term.vterm == nil || !term.active {
		return
	}

	for vt.output_get_buffer_current(term.vterm) > 0 {
		buffer: [4096]byte
		count := vt.output_read(term.vterm, raw_data(buffer[:]), c.size_t(len(buffer)))
		if count == 0 {
			return
		}
		posix.write(posix.FD(term.pty_fd), raw_data(buffer[:count]), count)
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

sync_pane_terminals :: proc(node: ^Node) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane != nil {
			bounds := node.pane.bounds
			terminal_spawn_shell(&node.pane.terminal, terminal_max_int(bounds.width - 2, 1), terminal_max_int(bounds.height - 2, 1))
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			sync_pane_terminals(child)
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return
		}
		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}
		sync_pane_terminals(node.children[index])
	}
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
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			changed = poll_pane_terminals(child) || changed
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return false
		}
		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}
		changed = poll_pane_terminals(node.children[index])
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
