package app

import "core:c"
import posix "core:sys/posix"

Input_Action_Kind :: enum {
	None,
	Quit,
	Command,
}

Input_Action :: struct {
	kind:    Input_Action_Kind,
	command: Command,
}

read_input_action :: proc() -> Input_Action {
	buffer: [1]byte
	count := posix.read(posix.FD(0), raw_data(buffer[:]), c.size_t(len(buffer)))
	if count <= 0 {
		return Input_Action{kind = .None}
	}

	key := buffer[0]
	switch key {
	case 'q':
		return Input_Action{kind = .Quit}
	case 's':
		return Input_Action{kind = .Command, command = command_split_horizontal()}
	case 'v':
		return Input_Action{kind = .Command, command = command_split_vertical()}
	case 'w':
		return Input_Action{kind = .Command, command = command_close_pane()}
	case 'h':
		return Input_Action{kind = .Command, command = command_focus(.Left)}
	case 'j':
		return Input_Action{kind = .Command, command = command_focus(.Down)}
	case 'k':
		return Input_Action{kind = .Command, command = command_focus(.Up)}
	case 'l':
		return Input_Action{kind = .Command, command = command_focus(.Right)}
	case '1' ..= '9':
		return Input_Action{kind = .Command, command = command_switch_workspace(int(key - '0'))}
	}

	return Input_Action{kind = .None}
}
