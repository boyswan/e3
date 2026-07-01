package input

import domain "../app"

Mod_Key :: enum {
	Alt,
	Super,
}

Input_Mode :: enum {
	Normal,
	Resize,
}

Key_Bindings :: struct {
	quit:         string,
	split_right:  string,
	split_down:   string,
	open_pane:    string,
	close_pane:   string,
	dump_tree:    string,
	resize_mode:  string,
	focus_left:   string,
	focus_down:   string,
	focus_up:     string,
	focus_right:  string,
	move_left:    string,
	move_down:    string,
	move_up:      string,
	move_right:   string,
	workspace_1:  string,
	workspace_2:  string,
	workspace_3:  string,
	workspace_4:  string,
	workspace_5:  string,
	workspace_6:  string,
	workspace_7:  string,
	workspace_8:  string,
	workspace_9:  string,
}

key_bindings_default :: proc() -> Key_Bindings {
	return Key_Bindings {
		quit = "q",
		split_right = "d",
		split_down = "shift+d",
		open_pane = "enter",
		close_pane = "w",
		dump_tree = "t",
		resize_mode = "r",
		focus_left = "h",
		focus_down = "j",
		focus_up = "k",
		focus_right = "l",
		move_left = "shift+h",
		move_down = "shift+j",
		move_up = "shift+k",
		move_right = "shift+l",
		workspace_1 = "1",
		workspace_2 = "2",
		workspace_3 = "3",
		workspace_4 = "4",
		workspace_5 = "5",
		workspace_6 = "6",
		workspace_7 = "7",
		workspace_8 = "8",
		workspace_9 = "9",
	}
}

Action_Kind :: enum {
	None,
	Quit,
	Command,
	Pane_Input,
	Paste_Clipboard,
	Enter_Resize_Mode,
	Exit_Resize_Mode,
}

Action :: struct {
	kind:       Action_Kind,
	command:    domain.Command,
	input_data: [8]byte,
	input_len:  int,
}

pane_input_action :: proc(key: byte) -> Action {
	action := Action{kind = .Pane_Input, input_len = 1}
	action.input_data[0] = key
	return action
}

bytes_input_action :: proc(data: []byte) -> Action {
	action := Action{kind = .Pane_Input}
	for index in 0 ..< len(data) {
		if index >= len(action.input_data) {
			break
		}
		action.input_data[index] = data[index]
		action.input_len += 1
	}
	return action
}
