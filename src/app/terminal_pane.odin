package app

import "core:c"
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
		argv := [?]cstring{"/bin/sh", nil}
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
	term.cells = make([]byte, width * height)
	terminal_clear_grid(term)

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
	for byte_value in data {
		terminal_put_output_byte(term, byte_value)
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
			term.escape = 2
			return
		}
		if value == ']' {
			term.escape = 3
			return
		}
		term.escape = 0
	case 2:
		if value >= 0x40 && value <= 0x7e {
			term.escape = 0
		}
	case 3:
		if value == 0x07 {
			term.escape = 0
			return
		}
		if value == 0x1b {
			term.escape = 4
		}
	case 4:
		if value == '\\' {
			term.escape = 0
		} else {
			term.escape = 3
		}
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
