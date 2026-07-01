package sdl

import domain "../app"
import input "../input"
import sdl3 "vendor:sdl3"

read_input_action :: proc(mod_key: input.Mod_Key, bindings: input.Key_Bindings) -> input.Action {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT, .WINDOW_CLOSE_REQUESTED:
			return input.Action{kind = .Quit}
		case .KEY_DOWN:
			action := key_action(event.key, mod_key, bindings)
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

	return input.Action{kind = .None}
}

wait :: proc(timeout_ms: int) {
	sdl3.Delay(u32(timeout_ms))
}

key_action :: proc(event: sdl3.KeyboardEvent, mod_key: input.Mod_Key, bindings: input.Key_Bindings) -> input.Action {
	ctrl := event.mod & sdl3.KMOD_CTRL != {}
	shift := event.mod & sdl3.KMOD_SHIFT != {}

	if mod_key_pressed(event.mod, mod_key) {
		return mod_key_action(event.key, shift, bindings)
	}

	if ctrl {
		action := ctrl_key_action(event.key)
		if action.kind != .None {
			return action
		}
	}

	switch event.key {
	case sdl3.K_RETURN, sdl3.K_KP_ENTER:
		return input.bytes_input_action([]byte{0x0d})
	case sdl3.K_BACKSPACE:
		return input.bytes_input_action([]byte{0x7f})
	case sdl3.K_TAB:
		return input.bytes_input_action([]byte{0x09})
	case sdl3.K_ESCAPE:
		return input.bytes_input_action([]byte{0x1b})
	case sdl3.K_UP:
		return input.bytes_input_action([]byte{0x1b, '[', 'A'})
	case sdl3.K_DOWN:
		return input.bytes_input_action([]byte{0x1b, '[', 'B'})
	case sdl3.K_RIGHT:
		return input.bytes_input_action([]byte{0x1b, '[', 'C'})
	case sdl3.K_LEFT:
		return input.bytes_input_action([]byte{0x1b, '[', 'D'})
	case sdl3.K_HOME:
		return input.bytes_input_action([]byte{0x1b, '[', 'H'})
	case sdl3.K_END:
		return input.bytes_input_action([]byte{0x1b, '[', 'F'})
	case sdl3.K_DELETE:
		return input.bytes_input_action([]byte{0x1b, '[', '3', '~'})
	case sdl3.K_PAGEUP:
		return input.bytes_input_action([]byte{0x1b, '[', '5', '~'})
	case sdl3.K_PAGEDOWN:
		return input.bytes_input_action([]byte{0x1b, '[', '6', '~'})
	}

	return input.Action{kind = .None}
}

mod_key_pressed :: proc(mod: sdl3.Keymod, mod_key: input.Mod_Key) -> bool {
	switch mod_key {
	case .Alt:
		return mod & sdl3.KMOD_ALT != {}
	case .Super:
		return mod & sdl3.KMOD_GUI != {}
	}
	return false
}

ctrl_key_action :: proc(key: sdl3.Keycode) -> input.Action {
	switch key {
	case sdl3.K_A: return input.bytes_input_action([]byte{0x01})
	case sdl3.K_B: return input.bytes_input_action([]byte{0x02})
	case sdl3.K_C: return input.bytes_input_action([]byte{0x03})
	case sdl3.K_D: return input.bytes_input_action([]byte{0x04})
	case sdl3.K_E: return input.bytes_input_action([]byte{0x05})
	case sdl3.K_F: return input.bytes_input_action([]byte{0x06})
	case sdl3.K_G: return input.bytes_input_action([]byte{0x07})
	case sdl3.K_H: return input.bytes_input_action([]byte{0x08})
	case sdl3.K_I: return input.bytes_input_action([]byte{0x09})
	case sdl3.K_J: return input.bytes_input_action([]byte{0x0a})
	case sdl3.K_K: return input.bytes_input_action([]byte{0x0b})
	case sdl3.K_L: return input.bytes_input_action([]byte{0x0c})
	case sdl3.K_M: return input.bytes_input_action([]byte{0x0d})
	case sdl3.K_N: return input.bytes_input_action([]byte{0x0e})
	case sdl3.K_O: return input.bytes_input_action([]byte{0x0f})
	case sdl3.K_P: return input.bytes_input_action([]byte{0x10})
	case sdl3.K_Q: return input.bytes_input_action([]byte{0x11})
	case sdl3.K_R: return input.bytes_input_action([]byte{0x12})
	case sdl3.K_S: return input.bytes_input_action([]byte{0x13})
	case sdl3.K_T: return input.bytes_input_action([]byte{0x14})
	case sdl3.K_U: return input.bytes_input_action([]byte{0x15})
	case sdl3.K_V: return input.bytes_input_action([]byte{0x16})
	case sdl3.K_W: return input.bytes_input_action([]byte{0x17})
	case sdl3.K_X: return input.bytes_input_action([]byte{0x18})
	case sdl3.K_Y: return input.bytes_input_action([]byte{0x19})
	case sdl3.K_Z: return input.bytes_input_action([]byte{0x1a})
	case sdl3.K_LEFTBRACKET: return input.bytes_input_action([]byte{0x1b})
	case sdl3.K_BACKSLASH: return input.bytes_input_action([]byte{0x1c})
	case sdl3.K_RIGHTBRACKET: return input.bytes_input_action([]byte{0x1d})
	case sdl3.K_6: return input.bytes_input_action([]byte{0x1e})
	case sdl3.K_MINUS: return input.bytes_input_action([]byte{0x1f})
	case sdl3.K_SPACE: return input.bytes_input_action([]byte{0x00})
	}

	return input.Action{kind = .None}
}

mod_key_action :: proc(key: sdl3.Keycode, shift: bool, bindings: input.Key_Bindings) -> input.Action {
	if key_matches(key, shift, bindings.quit) {
		return input.Action{kind = .Quit}
	}
	if key_matches(key, shift, bindings.split_right) {
		return input.Action{kind = .Command, command = domain.command_set_split_right()}
	}
	if key_matches(key, shift, bindings.split_down) {
		return input.Action{kind = .Command, command = domain.command_set_split_down()}
	}
	if key_matches(key, shift, bindings.open_pane) {
		return input.Action{kind = .Command, command = domain.command_open_pane()}
	}
	if key_matches(key, shift, bindings.close_pane) {
		return input.Action{kind = .Command, command = domain.command_close_pane()}
	}
	if key_matches(key, shift, bindings.dump_tree) {
		return input.Action{kind = .Command, command = domain.command_dump_tree()}
	}
	if key_matches(key, shift, bindings.focus_left) {
		return input.Action{kind = .Command, command = domain.command_focus(.Left)}
	}
	if key_matches(key, shift, bindings.focus_down) {
		return input.Action{kind = .Command, command = domain.command_focus(.Down)}
	}
	if key_matches(key, shift, bindings.focus_up) {
		return input.Action{kind = .Command, command = domain.command_focus(.Up)}
	}
	if key_matches(key, shift, bindings.focus_right) {
		return input.Action{kind = .Command, command = domain.command_focus(.Right)}
	}
	if key_matches(key, shift, bindings.workspace_1) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(1)}
	}
	if key_matches(key, shift, bindings.workspace_2) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(2)}
	}
	if key_matches(key, shift, bindings.workspace_3) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(3)}
	}
	if key_matches(key, shift, bindings.workspace_4) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(4)}
	}
	if key_matches(key, shift, bindings.workspace_5) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(5)}
	}
	if key_matches(key, shift, bindings.workspace_6) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(6)}
	}
	if key_matches(key, shift, bindings.workspace_7) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(7)}
	}
	if key_matches(key, shift, bindings.workspace_8) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(8)}
	}
	if key_matches(key, shift, bindings.workspace_9) {
		return input.Action{kind = .Command, command = domain.command_switch_workspace(9)}
	}

	return input.Action{kind = .None}
}

key_matches :: proc(key: sdl3.Keycode, shift: bool, spec: string) -> bool {
	if spec == "" {
		return false
	}

	expected_shift := false
	name := spec
	if len(spec) > 6 && spec[:6] == "shift+" {
		expected_shift = true
		name = spec[6:]
	}

	if shift != expected_shift {
		return false
	}

	return key_name_matches(key, name)
}

key_name_matches :: proc(key: sdl3.Keycode, name: string) -> bool {
	if len(name) == 1 {
		ch := name[0]
		if ch >= 'a' && ch <= 'z' {
			return key == sdl3.Keycode(ch)
		}
		if ch >= '0' && ch <= '9' {
			return key == sdl3.Keycode(ch)
		}
	}

	switch name {
	case "enter", "return": return key == sdl3.K_RETURN || key == sdl3.K_KP_ENTER
	case "space": return key == sdl3.K_SPACE
	case "tab": return key == sdl3.K_TAB
	case "escape", "esc": return key == sdl3.K_ESCAPE
	case "backspace": return key == sdl3.K_BACKSPACE
	case "left": return key == sdl3.K_LEFT
	case "right": return key == sdl3.K_RIGHT
	case "up": return key == sdl3.K_UP
	case "down": return key == sdl3.K_DOWN
	}

	return false
}

cstring_input_action :: proc(text: cstring) -> input.Action {
	if text == nil {
		return input.Action{kind = .None}
	}

	data := ([^]byte)(text)
	action := input.Action{kind = .Pane_Input}
	for action.input_len < len(action.input_data) && data[action.input_len] != 0 {
		action.input_data[action.input_len] = data[action.input_len]
		action.input_len += 1
	}

	if action.input_len == 0 {
		return input.Action{kind = .None}
	}

	return action
}
