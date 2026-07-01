package tty

import "core:c"
import domain "../app"
import input "../input"
import posix "core:sys/posix"

wait :: proc(timeout_ms: int) -> bool {
	poll_fd := posix.pollfd {
		fd = posix.FD(0),
		events = {.IN},
	}

	return posix.poll(&poll_fd, 1, c.int(timeout_ms)) > 0
}

read_input_action :: proc(mode := input.Input_Mode.Normal) -> input.Action {
	if mode == .Resize {
		return read_resize_input_action()
	}

	key, ok := read_input_byte()
	if !ok {
		return input.Action{kind = .None}
	}

	// Option/Alt is represented by most terminals as ESC followed by the key.
	if key == 0x1b {
		modified_key, modified_ok := read_input_byte()
		if !modified_ok {
			return input.pane_input_action(key)
		}

		action := action_from_modified_key(modified_key)
		if action.kind != .None {
			return action
		}

		return input.pane_input_action(modified_key)
	}

	return input.pane_input_action(key)
}

read_input_byte :: proc() -> (byte, bool) {
	buffer: [1]byte
	count := posix.read(posix.FD(0), raw_data(buffer[:]), c.size_t(len(buffer)))
	if count <= 0 {
		return 0, false
	}

	return buffer[0], true
}

action_from_modified_key :: proc(key: byte) -> input.Action {
	switch key {
	case 'q':
		return input.Action{kind = .Quit}
	case 'd':
		return input.Action{kind = .Command, command = domain.command_set_split_right()}
	case 'D':
		return input.Action{kind = .Command, command = domain.command_set_split_down()}
	case '\r', '\n':
		return input.Action{kind = .Command, command = domain.command_open_pane()}
	case 'w':
		return input.Action{kind = .Command, command = domain.command_close_pane()}
	case 'W':
		return input.Action{kind = .Command, command = domain.command_layout_tabbed()}
	case 'S':
		return input.Action{kind = .Command, command = domain.command_layout_stacking()}
	case 't':
		return input.Action{kind = .Command, command = domain.command_dump_tree()}
	case 'r':
		return input.Action{kind = .Enter_Resize_Mode}
	case 'E':
		return input.Action{kind = .Command, command = domain.command_layout_toggle_split()}
	case 'h':
		return input.Action{kind = .Command, command = domain.command_focus(.Left)}
	case 'j':
		return input.Action{kind = .Command, command = domain.command_focus(.Down)}
	case 'k':
		return input.Action{kind = .Command, command = domain.command_focus(.Up)}
	case 'l':
		return input.Action{kind = .Command, command = domain.command_focus(.Right)}
	case 'u':
		return input.Action{kind = .Command, command = domain.command_scroll_pane(10)}
	case 'U':
		return input.Action{kind = .Command, command = domain.command_scroll_pane(-10)}
	case 'H':
		return input.Action{kind = .Command, command = domain.command_move_pane(.Left)}
	case 'J':
		return input.Action{kind = .Command, command = domain.command_move_pane(.Down)}
	case 'K':
		return input.Action{kind = .Command, command = domain.command_move_pane(.Up)}
	case 'L':
		return input.Action{kind = .Command, command = domain.command_move_pane(.Right)}
	case '1' ..= '9':
		return input.Action{kind = .Command, command = domain.command_switch_workspace(int(key - '0'))}
	}

	return input.Action{kind = .None}
}

read_resize_input_action :: proc() -> input.Action {
	key, ok := read_input_byte()
	if !ok {
		return input.Action{kind = .None}
	}

	switch key {
	case 0x1b, '\r', '\n':
		return input.Action{kind = .Exit_Resize_Mode}
	case 'h':
		return input.Action{kind = .Command, command = domain.command_resize_shrink_width()}
	case 'l':
		return input.Action{kind = .Command, command = domain.command_resize_grow_width()}
	case 'k':
		return input.Action{kind = .Command, command = domain.command_resize_shrink_height()}
	case 'j':
		return input.Action{kind = .Command, command = domain.command_resize_grow_height()}
	}

	return input.Action{kind = .None}
}
