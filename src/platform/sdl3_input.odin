package platform

import domain "../app"
import sdl "vendor:sdl3"

read_sdl3_input_action :: proc() -> Input_Action {
	event: sdl.Event
	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT, .WINDOW_CLOSE_REQUESTED:
			return Input_Action{kind = .Quit}
		case .KEY_DOWN:
			action := sdl3_key_action(event.key)
			if action.kind != .None {
				return action
			}
		case .TEXT_INPUT:
			action := cstring_input_action(event.text.text)
			if action.kind != .None {
				return action
			}
		}
	}

	return Input_Action{kind = .None}
}

sdl3_input_wait :: proc(timeout_ms: int) {
	sdl.Delay(u32(timeout_ms))
}

sdl3_key_action :: proc(event: sdl.KeyboardEvent) -> Input_Action {
	alt := event.mod & sdl.KMOD_ALT != {}
	shift := event.mod & sdl.KMOD_SHIFT != {}

	if alt {
		return sdl3_alt_key_action(event.key, shift)
	}

	// Keep raw q as an emergency/dev quit key while this is still a prototype.
	if event.key == sdl.K_Q {
		return Input_Action{kind = .Quit}
	}

	switch event.key {
	case sdl.K_RETURN, sdl.K_KP_ENTER:
		return bytes_input_action([]byte{0x0d})
	case sdl.K_BACKSPACE:
		return bytes_input_action([]byte{0x7f})
	case sdl.K_TAB:
		return bytes_input_action([]byte{0x09})
	case sdl.K_ESCAPE:
		return bytes_input_action([]byte{0x1b})
	case sdl.K_UP:
		return bytes_input_action([]byte{0x1b, '[', 'A'})
	case sdl.K_DOWN:
		return bytes_input_action([]byte{0x1b, '[', 'B'})
	case sdl.K_RIGHT:
		return bytes_input_action([]byte{0x1b, '[', 'C'})
	case sdl.K_LEFT:
		return bytes_input_action([]byte{0x1b, '[', 'D'})
	case sdl.K_HOME:
		return bytes_input_action([]byte{0x1b, '[', 'H'})
	case sdl.K_END:
		return bytes_input_action([]byte{0x1b, '[', 'F'})
	case sdl.K_DELETE:
		return bytes_input_action([]byte{0x1b, '[', '3', '~'})
	case sdl.K_PAGEUP:
		return bytes_input_action([]byte{0x1b, '[', '5', '~'})
	case sdl.K_PAGEDOWN:
		return bytes_input_action([]byte{0x1b, '[', '6', '~'})
	}

	return Input_Action{kind = .None}
}

sdl3_alt_key_action :: proc(key: sdl.Keycode, shift: bool) -> Input_Action {
	switch key {
	case sdl.K_Q:
		return Input_Action{kind = .Quit}
	case sdl.K_D:
		if shift {
			return Input_Action{kind = .Command, command = domain.command_set_split_down()}
		}
		return Input_Action{kind = .Command, command = domain.command_set_split_right()}
	case sdl.K_RETURN, sdl.K_KP_ENTER:
		return Input_Action{kind = .Command, command = domain.command_open_pane()}
	case sdl.K_W:
		return Input_Action{kind = .Command, command = domain.command_close_pane()}
	case sdl.K_T:
		return Input_Action{kind = .Command, command = domain.command_dump_tree()}
	case sdl.K_H:
		return Input_Action{kind = .Command, command = domain.command_focus(.Left)}
	case sdl.K_J:
		return Input_Action{kind = .Command, command = domain.command_focus(.Down)}
	case sdl.K_K:
		return Input_Action{kind = .Command, command = domain.command_focus(.Up)}
	case sdl.K_L:
		return Input_Action{kind = .Command, command = domain.command_focus(.Right)}
	case sdl.K_1:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(1)}
	case sdl.K_2:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(2)}
	case sdl.K_3:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(3)}
	case sdl.K_4:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(4)}
	case sdl.K_5:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(5)}
	case sdl.K_6:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(6)}
	case sdl.K_7:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(7)}
	case sdl.K_8:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(8)}
	case sdl.K_9:
		return Input_Action{kind = .Command, command = domain.command_switch_workspace(9)}
	}

	return Input_Action{kind = .None}
}

cstring_input_action :: proc(text: cstring) -> Input_Action {
	if text == nil {
		return Input_Action{kind = .None}
	}

	data := ([^]byte)(text)
	action := Input_Action{kind = .Pane_Input}
	for action.input_len < len(action.input_data) && data[action.input_len] != 0 {
		action.input_data[action.input_len] = data[action.input_len]
		action.input_len += 1
	}

	if action.input_len == 0 {
		return Input_Action{kind = .None}
	}

	return action
}

bytes_input_action :: proc(data: []byte) -> Input_Action {
	action := Input_Action{kind = .Pane_Input}
	for index in 0 ..< len(data) {
		if index >= len(action.input_data) {
			break
		}
		action.input_data[index] = data[index]
		action.input_len += 1
	}
	return action
}
