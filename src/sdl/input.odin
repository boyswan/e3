package sdl

import domain "../app"
import input "../input"
import render "../render"
import sdl3 "vendor:sdl3"

read_input_action :: proc(state: ^State, surface: ^render.Screen_Buffer, mode: input.Input_Mode, mod_key: input.Mod_Key, bindings: input.Key_Bindings) -> input.Action {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT, .WINDOW_CLOSE_REQUESTED:
			return input.Action{kind = .Quit}
		case .KEY_DOWN:
			action := key_action(state, surface, mode, event.key, mod_key, bindings)
			if action.kind != .None {
				return action
			}
		case .MOUSE_BUTTON_DOWN:
			handle_mouse_button_down(state, surface, event.button)
		case .MOUSE_MOTION:
			handle_mouse_motion(state, surface, event.motion)
		case .MOUSE_BUTTON_UP:
			handle_mouse_button_up(state, surface, event.button)
		case .MOUSE_WHEEL:
			if mode == .Normal {
				lines := int(event.wheel.y) * 3
				if lines != 0 {
					return input.Action{kind = .Command, command = domain.command_scroll_pane(lines)}
				}
			}
		case .TEXT_INPUT:
			if mode == .Normal {
				action := cstring_input_action(event.text.text)
				if action.kind != .None {
					return action
				}
			}
		}
	}

	return input.Action{kind = .None}
}

clipboard_text :: proc() -> []byte {
	text := sdl3.GetClipboardText()
	if text == nil {
		return nil
	}
	defer sdl3.free(rawptr(text))

	result := make([dynamic]byte)
	index := 0
	for text[index] != 0 {
		append(&result, byte(text[index]))
		index += 1
	}

	return result[:]
}

wait :: proc(timeout_ms: int) {
	sdl3.Delay(u32(timeout_ms))
}

key_action :: proc(state: ^State, surface: ^render.Screen_Buffer, mode: input.Input_Mode, event: sdl3.KeyboardEvent, mod_key: input.Mod_Key, bindings: input.Key_Bindings) -> input.Action {
	ctrl := event.mod & sdl3.KMOD_CTRL != {}
	shift := event.mod & sdl3.KMOD_SHIFT != {}
	gui := event.mod & sdl3.KMOD_GUI != {}

	if mode == .Resize {
		return resize_mode_key_action(event, mod_key, bindings)
	}

	if (gui && event.key == sdl3.K_C) || (ctrl && shift && event.key == sdl3.K_C) || event.key == sdl3.K_COPY {
		copy_selection_to_clipboard(state, surface)
		return input.Action{kind = .None}
	}
	if (gui && event.key == sdl3.K_V) || (ctrl && shift && event.key == sdl3.K_V) || event.key == sdl3.K_PASTE {
		return input.Action{kind = .Paste_Clipboard}
	}

	if mod_key_pressed(event.mod, mod_key) {
		if event.key == sdl3.K_PAGEUP {
			return input.Action{kind = .Command, command = domain.command_scroll_pane(10)}
		}
		if event.key == sdl3.K_PAGEDOWN {
			return input.Action{kind = .Command, command = domain.command_scroll_pane(-10)}
		}
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

resize_mode_key_action :: proc(event: sdl3.KeyboardEvent, mod_key: input.Mod_Key, bindings: input.Key_Bindings) -> input.Action {
	shift := event.mod & sdl3.KMOD_SHIFT != {}
	if event.key == sdl3.K_ESCAPE || event.key == sdl3.K_RETURN || event.key == sdl3.K_KP_ENTER {
		return input.Action{kind = .Exit_Resize_Mode}
	}
	if mod_key_pressed(event.mod, mod_key) && key_matches(event.key, shift, bindings.resize_mode) {
		return input.Action{kind = .Exit_Resize_Mode}
	}

	switch event.key {
	case sdl3.K_H, sdl3.K_LEFT:
		return input.Action{kind = .Command, command = domain.command_resize_shrink_width()}
	case sdl3.K_L, sdl3.K_RIGHT:
		return input.Action{kind = .Command, command = domain.command_resize_grow_width()}
	case sdl3.K_K, sdl3.K_UP:
		return input.Action{kind = .Command, command = domain.command_resize_shrink_height()}
	case sdl3.K_J, sdl3.K_DOWN:
		return input.Action{kind = .Command, command = domain.command_resize_grow_height()}
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
	if key_matches(key, shift, bindings.resize_mode) {
		return input.Action{kind = .Enter_Resize_Mode}
	}
	if key_matches(key, shift, bindings.fullscreen_toggle) {
		return input.Action{kind = .Command, command = domain.command_fullscreen_toggle()}
	}
	if key_matches(key, shift, bindings.layout_toggle_split) {
		return input.Action{kind = .Command, command = domain.command_layout_toggle_split()}
	}
	if key_matches(key, shift, bindings.layout_tabbed) {
		return input.Action{kind = .Command, command = domain.command_layout_tabbed()}
	}
	if key_matches(key, shift, bindings.layout_stacking) {
		return input.Action{kind = .Command, command = domain.command_layout_stacking()}
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
	if key_matches(key, shift, bindings.move_left) {
		return input.Action{kind = .Command, command = domain.command_move_pane(.Left)}
	}
	if key_matches(key, shift, bindings.move_down) {
		return input.Action{kind = .Command, command = domain.command_move_pane(.Down)}
	}
	if key_matches(key, shift, bindings.move_up) {
		return input.Action{kind = .Command, command = domain.command_move_pane(.Up)}
	}
	if key_matches(key, shift, bindings.move_right) {
		return input.Action{kind = .Command, command = domain.command_move_pane(.Right)}
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
	if key_matches(key, shift, bindings.move_to_workspace_1) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(1)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_2) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(2)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_3) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(3)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_4) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(4)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_5) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(5)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_6) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(6)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_7) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(7)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_8) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(8)}
	}
	if key_matches(key, shift, bindings.move_to_workspace_9) {
		return input.Action{kind = .Command, command = domain.command_move_pane_to_workspace(9)}
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

handle_mouse_button_down :: proc(state: ^State, surface: ^render.Screen_Buffer, event: sdl3.MouseButtonEvent) {
	if event.button != sdl3.BUTTON_LEFT {
		return
	}

	x, y, ok := mouse_cell_position(state, surface, event.x, event.y)
	if !ok {
		state.selecting = false
		state.selection_valid = false
		return
	}

	state.selecting = true
	state.selection_valid = false
	state.selection_start_x = x
	state.selection_start_y = y
	state.selection_end_x = x
	state.selection_end_y = y
}

handle_mouse_motion :: proc(state: ^State, surface: ^render.Screen_Buffer, event: sdl3.MouseMotionEvent) {
	if !state.selecting || event.state & sdl3.BUTTON_LMASK == {} {
		return
	}

	x, y, ok := mouse_cell_position(state, surface, event.x, event.y)
	if !ok {
		return
	}

	state.selection_end_x = x
	state.selection_end_y = y
	state.selection_valid = x != state.selection_start_x || y != state.selection_start_y
}

handle_mouse_button_up :: proc(state: ^State, surface: ^render.Screen_Buffer, event: sdl3.MouseButtonEvent) {
	if event.button != sdl3.BUTTON_LEFT || !state.selecting {
		return
	}

	state.selecting = false
	x, y, ok := mouse_cell_position(state, surface, event.x, event.y)
	if ok {
		state.selection_end_x = x
		state.selection_end_y = y
	}

	state.selection_valid = state.selection_end_x != state.selection_start_x || state.selection_end_y != state.selection_start_y
	if state.selection_valid {
		copy_selection_to_clipboard(state, surface)
	}
}

mouse_cell_position :: proc(state: ^State, surface: ^render.Screen_Buffer, mouse_x: f32, mouse_y: f32) -> (int, int, bool) {
	if state.cell_width <= 0 || state.cell_height <= 0 || surface.width <= 0 || surface.height <= 0 {
		return 0, 0, false
	}

	// Mouse events are delivered in window points; cell metrics are in backing
	// pixels on high-density displays.
	x := int(mouse_x * state.pixel_scale) / state.cell_width
	y := int(mouse_y * state.pixel_scale) / state.cell_height
	if x < 0 { x = 0 }
	if y < 0 { y = 0 }
	if x >= surface.width { x = surface.width - 1 }
	if y >= surface.height { y = surface.height - 1 }
	return x, y, true
}

copy_selection_to_clipboard :: proc(state: ^State, surface: ^render.Screen_Buffer) {
	start_x, start_y, end_x, end_y := normalized_selection(state)
	bytes := make([dynamic]byte)
	defer delete(bytes)

	for y in start_y ..= end_y {
		row_start := 0
		row_end := surface.width - 1
		if y == start_y {
			row_start = start_x
		}
		if y == end_y {
			row_end = end_x
		}

		for row_end >= row_start && selection_cell_is_blank(surface.cells[y * surface.width + row_end]) {
			row_end -= 1
		}

		for x in row_start ..= row_end {
			append_selection_cell_text(&bytes, surface.cells[y * surface.width + x])
		}
		if y != end_y {
			append(&bytes, '\n')
		}
	}

	if len(bytes) == 0 {
		return
	}

	append(&bytes, 0)
	_ = sdl3.SetClipboardText(cstring(raw_data(bytes[:])))
	_ = sdl3.SetPrimarySelectionText(cstring(raw_data(bytes[:])))
}

selection_cell_is_blank :: proc(cell: render.Cell) -> bool {
	return cell.rune == 0 && cell.glyph == " " && cell.line_mask == 0
}

append_selection_cell_text :: proc(bytes: ^[dynamic]byte, cell: render.Cell) {
	if cell.rune != 0 {
		buf: [4]u8
		count := encode_utf8(cell.rune, buf[:])
		for index in 0 ..< count {
			append(bytes, buf[index])
		}
		return
	}

	if cell.glyph == "" {
		append(bytes, ' ')
		return
	}

	for index in 0 ..< len(cell.glyph) {
		append(bytes, cell.glyph[index])
	}
}
