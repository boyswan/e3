package main

import domain "./app"
import platform "./platform"
import ui "./render"

main :: proc() {
	state: domain.App
	domain.init_app(&state)

	domain.execute_command(&state, domain.command_set_split_right())
	domain.execute_command(&state, domain.command_open_pane())
	domain.execute_command(&state, domain.command_set_split_down())
	domain.execute_command(&state, domain.command_open_pane())
	domain.execute_command(&state, domain.command_switch_workspace(2))
	domain.execute_command(&state, domain.command_set_split_down())
	domain.execute_command(&state, domain.command_open_pane())
	domain.execute_command(&state, domain.command_switch_workspace(1))

	width, height := platform.terminal_size_or_default(80, 24)
	renderer := ui.renderer_make(.TTY, width, height)
	defer ui.renderer_destroy(&renderer)

	ui.renderer_begin(&renderer)
	defer ui.renderer_end(&renderer)

	mode: platform.Terminal_Mode
	platform.terminal_enter_raw_mode(&mode)
	defer platform.terminal_restore_mode(&mode)

	running := true
	for running {
		domain.poll_all_terminals(&state)

		new_width, new_height := platform.terminal_size_or_default(80, 24)
		ui.renderer_resize(&renderer, new_width, new_height)

		ui.render_app(&renderer.surface, &state, domain.Rect {
			x = 0,
			y = 0,
			width = ui.renderer_width(&renderer),
			height = ui.renderer_height(&renderer),
		})
		ui.renderer_present(&renderer)

		if !platform.input_wait(50) {
			continue
		}

		action := platform.read_input_action()
		switch action.kind {
		case .None:
			// Ignore unknown input.
		case .Quit:
			running = false
		case .Command:
			domain.execute_command(&state, action.command)
		case .Pane_Input:
			domain.write_focused_terminal(&state, action.input_data[:action.input_len])
		}
	}
}
