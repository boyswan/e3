package platform

import "core:c"
import domain "../app"
import posix "core:sys/posix"

Input_Action_Kind :: enum {
	None,
	Quit,
	Command,
	Pane_Input,
}

Input_Action :: struct {
	kind:       Input_Action_Kind,
	command:    domain.Command,
	input_data: [8]byte,
	input_len:  int,
}

input_wait :: proc(timeout_ms: int) -> bool {
	poll_fd := posix.pollfd {
		fd = posix.FD(0),
		events = {.IN},
	}

	return posix.poll(&poll_fd, 1, c.int(timeout_ms)) > 0
}

read_input_action :: proc() -> Input_Action {
	key, ok := read_input_byte()
	if !ok {
		return Input_Action{kind = .None}
	}

	// Keep raw q as an emergency/dev quit key.
	if key == 'q' {
		return Input_Action{kind = .Quit}
	}

	// Option/Alt is represented by most terminals as ESC followed by the key.
	if key == 0x1b {
		modified_key, modified_ok := read_input_byte()
		if !modified_ok {
			return pane_input_action(key)
		}

		action := action_from_modified_key(modified_key)
		if action.kind != .None {
			return action
		}

		return pane_input_action(modified_key)
	}

	return pane_input_action(key)
}

pane_input_action :: proc(key: byte) -> Input_Action {
	action := Input_Action{kind = .Pane_Input, input_len = 1}
	action.input_data[0] = key
	return action
}

read_input_byte :: proc() -> (byte, bool) {
	buffer: [1]byte
	count := posix.read(posix.FD(0), raw_data(buffer[:]), c.size_t(len(buffer)))
	if count <= 0 {
		return 0, false
	}

	return buffer[0], true
}

action_from_modified_key :: proc(key: byte) -> Input_Action {
	switch key {
	case 'q':
		return Input_Action{kind = .Quit}
	case 'd':
		return Input_Action{kind = .Command, command = domain.command_set_split_right()}
	case 'D':
		return Input_Action{kind = .Command, command = domain.command_set_split_down()}
	case '\r', '\n':
		return Input_Action{kind = .Command, command = domain.command_open_pane()}
	case 'w':
		return Input_Action{kind = .Command, command = domain.command_close_pane()}
	case 't':
		return Input_Action{kind = .Command, command = domain.command_dump_tree()}
	case 'h':
		return Input_Action{kind = .Command, command = domain.command_focus(.Left)}
	case 'j':
		return Input_Action{kind = .Command, command = domain.command_focus(.Down)}
	case 'k':
		return Input_Action{kind = .Command, command = domain.command_focus(.Up)}
	case 'l':
		return Input_Action{kind = .Command, command = domain.command_focus(.Right)}
	case '1' ..= '9':
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(int(key - '0'))}
	}

	return Input_Action{kind = .None}
}
