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

	input_mode := input.Input_Mode.Normal
	running := true
	for running {
		domain.poll_all_terminals(&state)

		new_width, new_height := tty.size_or_default(80, 24)
		if renderer_kind == .SDL3 {
			new_width = renderer.width(&r)
			new_height = renderer.height(&r)
		}
		renderer.resize(&r, new_width, new_height)

		terminal_width_padding := 0
		terminal_height_padding := 0
		if renderer_kind == .SDL3 {
			content_inset := config.renderer.native_pane_padding_px + config.renderer.native_pane_border_px
			terminal_width_padding = ceil_div(content_inset * 2, renderer.cell_width(&r))
			terminal_height_padding = ceil_div(content_inset * 2, renderer.cell_height(&r))
		}

		render.render_app(
			&r.surface,
			&state,
			domain.Rect{x = 0, y = 0, width = renderer.width(&r), height = renderer.height(&r)},
			input_mode,
			renderer_kind == .SDL3,
			terminal_width_padding,
			terminal_height_padding,
		)
		renderer.present(&r, &state, input_mode)

		action := read_next_action(&r, input_mode, config.mod_key, config.bindings)
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
		case .Paste_Clipboard:
			if renderer_kind == .SDL3 {
				paste := native.clipboard_text()
				if paste != nil {
					domain.write_focused_terminal(&state, paste)
					delete(paste)
				}
			}
		case .Enter_Resize_Mode:
			input_mode = .Resize
		case .Exit_Resize_Mode:
			input_mode = .Normal
		}
	}
}

read_next_action :: proc(
	r: ^renderer.Renderer,
	mode: input.Input_Mode,
	mod_key: input.Mod_Key,
	bindings: input.Key_Bindings,
) -> input.Action {
	if r.kind == .TTY {
		if !tty.wait(50) {
			return input.Action{kind = .None}
		}
		return tty.read_input_action(mode)
	}

	action := native.read_input_action(&r.sdl, &r.surface, mode, mod_key, bindings)
	if action.kind == .None {
		native.wait(16)
	}
	return action
}

ceil_div :: proc(value: int, divisor: int) -> int {
	if divisor <= 0 {
		return 0
	}
	return (value + divisor - 1) / divisor
}

renderer_kind_from_args :: proc() -> renderer.Kind {
	for arg in os.args {
		if arg == "--tty" || arg == "--terminal" {
			return .TTY
		}
	}

	return .SDL3
}
