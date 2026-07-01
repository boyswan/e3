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

read_input_action :: proc() -> input.Action {
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
	case 't':
		return input.Action{kind = .Command, command = domain.command_dump_tree()}
	case 'h':
		return input.Action{kind = .Command, command = domain.command_focus(.Left)}
	case 'j':
		return input.Action{kind = .Command, command = domain.command_focus(.Down)}
	case 'k':
		return input.Action{kind = .Command, command = domain.command_focus(.Up)}
	case 'l':
		return input.Action{kind = .Command, command = domain.command_focus(.Right)}
	case '1' ..= '9':
		return input.Action{kind = .Command, command = domain.command_switch_workspace(int(key - '0'))}
	}

	return input.Action{kind = .None}
}
