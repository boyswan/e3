package main

import domain "./app"
import cfg "./config"
import input "./input"
import render "./render"
import logger "./debuglog"
import renderer "./renderer"
import native "./sdl"
import tty "./tty"
import "core:os"

main :: proc() {
	logger.init()
	logger.line("main: start")
	defer logger.line("main: exit")

	state: domain.App
	logger.line("main: init_app")
	domain.init_app(&state)
	logger.line("main: open initial pane")
	domain.execute_command(&state, domain.command_open_pane())

	renderer_kind := renderer_kind_from_args()
	logger.linef("main: renderer_kind=%v", renderer_kind)
	width, height := tty.size_or_default(80, 24)
	if renderer_kind == .SDL3 {
		width = 120
		height = 40
	}
	logger.linef("main: initial size %dx%d", width, height)
	config := cfg.load_config()
	logger.linef("main: config loaded font_family=%s font_path=%s font_size=%f", config.renderer.font_family, config.renderer.font_path, config.renderer.font_size)
	r := renderer.make(renderer_kind, width, height, config.renderer)
	defer renderer.destroy(&r)

	logger.line("main: renderer begin")
	renderer.begin(&r)
	logger.linef("main: renderer began surface=%dx%d", renderer.width(&r), renderer.height(&r))
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
	logged_first_frame := false
	for running {
		native_chrome := native_chrome_enabled(renderer_kind)
		domain.poll_all_terminals(&state)

		new_width, new_height := tty.size_or_default(80, 24)
		if renderer_kind == .SDL3 {
			new_width = renderer.width(&r)
			new_height = renderer.height(&r)
		}
		renderer.resize(&r, new_width, new_height)

		terminal_width_padding := 0
		terminal_height_padding := 0
		if native_chrome {
			content_inset := config.renderer.native_pane_padding_px + config.renderer.native_pane_border_px
			terminal_width_padding = ceil_div(content_inset * 2, renderer.cell_width(&r))
			terminal_height_padding = ceil_div(content_inset * 2, renderer.cell_height(&r))
		}

		render.render_app(
			&r.surface,
			&state,
			domain.Rect{x = 0, y = 0, width = renderer.width(&r), height = renderer.height(&r)},
			input_mode,
			native_chrome,
			terminal_width_padding,
			terminal_height_padding,
		)
		renderer.present(&r, &state, input_mode)
		if !logged_first_frame {
			logger.linef("main: first frame presented surface=%dx%d cell=%dx%d", renderer.width(&r), renderer.height(&r), renderer.cell_width(&r), renderer.cell_height(&r))
			logged_first_frame = true
		}

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

native_chrome_enabled :: proc(kind: renderer.Kind) -> bool {
	if kind != .SDL3 {
		return false
	}

	when ODIN_OS == .Darwin {
		return false
	} else {
		return true
	}
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
