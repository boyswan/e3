package main

import domain "./app"
import cfg "./config"
import input "./input"
import render "./render"
import renderer "./renderer"
import native "./sdl"
import tty "./tty"
import "core:os"

main :: proc() {
	state: domain.App
	domain.init_app(&state)
	domain.execute_command(&state, domain.command_open_pane())

	renderer_kind := renderer_kind_from_args()
	width, height := tty.size_or_default(80, 24)
	if renderer_kind == .SDL3 {
		width = 120
		height = 40
	}
	config := cfg.load_config()
	r := renderer.make(renderer_kind, width, height, config.renderer)
	defer renderer.destroy(&r)

	renderer.begin(&r)
	defer renderer.end(&r)

	mode: tty.Mode
	using_tty_mode := false
	if renderer_kind == .TTY {
		tty.enter_raw_mode(&mode)
		using_tty_mode = true
	}
	defer if using_tty_mode {
		tty.restore_mode(&mode)
	}

	running := true
	for running {
		domain.poll_all_terminals(&state)

		new_width, new_height := tty.size_or_default(80, 24)
		if renderer_kind == .SDL3 {
			new_width = renderer.width(&r)
			new_height = renderer.height(&r)
		}
		renderer.resize(&r, new_width, new_height)

		render.render_app(
			&r.surface,
			&state,
			domain.Rect{x = 0, y = 0, width = renderer.width(&r), height = renderer.height(&r)},
		)
		renderer.present(&r)

		action := read_next_action(renderer_kind, config.mod_key, config.bindings)
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

read_next_action :: proc(
	renderer_kind: renderer.Kind,
	mod_key: input.Mod_Key,
	bindings: input.Key_Bindings,
) -> input.Action {
	if renderer_kind == .TTY {
		if !tty.wait(50) {
			return input.Action{kind = .None}
		}
		return tty.read_input_action()
	}

	action := native.read_input_action(mod_key, bindings)
	if action.kind == .None {
		native.wait(16)
	}
	return action
}

renderer_kind_from_args :: proc() -> renderer.Kind {
	for arg in os.args {
		if arg == "--tty" || arg == "--terminal" {
			return .TTY
		}
	}

	return .SDL3
}
