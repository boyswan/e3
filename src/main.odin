package main

import domain "./app"
import "core:os"
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

	renderer_kind := renderer_kind_from_args()
	width, height := platform.terminal_size_or_default(80, 24)
	if renderer_kind == .SDL3 {
		width = 120
		height = 40
	}
	renderer := ui.renderer_make(renderer_kind, width, height)
	defer ui.renderer_destroy(&renderer)

	ui.renderer_begin(&renderer)
	defer ui.renderer_end(&renderer)

	mode: platform.Terminal_Mode
	using_tty_mode := false
	if renderer_kind == .TTY {
		platform.terminal_enter_raw_mode(&mode)
		using_tty_mode = true
	}
	defer if using_tty_mode {
		platform.terminal_restore_mode(&mode)
	}

	running := true
	for running {
		domain.poll_all_terminals(&state)

		new_width, new_height := platform.terminal_size_or_default(80, 24)
		if renderer_kind == .SDL3 {
			new_width = ui.renderer_width(&renderer)
			new_height = ui.renderer_height(&renderer)
		}
		ui.renderer_resize(&renderer, new_width, new_height)

		ui.render_app(&renderer.surface, &state, domain.Rect {
			x = 0,
			y = 0,
			width = ui.renderer_width(&renderer),
			height = ui.renderer_height(&renderer),
		})
		ui.renderer_present(&renderer)

		action := read_next_action(renderer_kind)
		if action.kind == .None {
			continue
		}

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

read_next_action :: proc(renderer_kind: ui.Renderer_Kind) -> platform.Input_Action {
	if renderer_kind == .TTY {
		if !platform.input_wait(50) {
			return platform.Input_Action{kind = .None}
		}
		return platform.read_input_action()
	}

	action := platform.read_sdl3_input_action()
	if action.kind == .None {
		platform.sdl3_input_wait(16)
	}
	return action
}

renderer_kind_from_args :: proc() -> ui.Renderer_Kind {
	for arg in os.args {
		if arg == "--tty" || arg == "--terminal" {
			return .TTY
		}
	}

	return .SDL3
}
