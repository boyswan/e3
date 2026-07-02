package main

import domain "../src/app"
import cfg "../src/config"
import input "../src/input"
import logger "../src/debuglog"
import render "../src/render"
import tty "../src/tty"

main :: proc() {
	logger.init()
	logger.line("src_tty: start")
	defer logger.line("src_tty: exit")

	state: domain.App
	domain.init_app(&state)
	domain.execute_command(&state, domain.command_open_pane())

	width, height := tty.size_or_default(80, 24)
	config := cfg.load_config()
	surface := render.make_screen_buffer(width, height)
	render.screen_set_background(&surface, config.renderer.background_r, config.renderer.background_g, config.renderer.background_b)
	render.screen_set_foreground(&surface, config.renderer.foreground_r, config.renderer.foreground_g, config.renderer.foreground_b)
	render.screen_set_palette(&surface, config.renderer.palette)
	render.screen_set_bar_colors(&surface, config.renderer.bar)
	defer render.destroy_screen_buffer(&surface)

	logger.linef("src_tty: initial size=%dx%d", width, height)
	logger.line("src_tty: enter_app_screen before")
	tty.enter_app_screen()
	logger.line("src_tty: enter_app_screen after")
	defer tty.leave_app_screen()

	mode: tty.Mode
	logger.line("src_tty: enter_raw_mode before")
	using_tty_mode := tty.enter_raw_mode(&mode)
	logger.linef("src_tty: enter_raw_mode after ok=%v", using_tty_mode)
	defer if using_tty_mode {
		tty.restore_mode(&mode)
	}

	input_mode := input.Input_Mode.Normal
	running := true
	logged_first_frame := false
	frame_index := 0
	for running {
		if frame_index < 3 {
			logger.linef("src_tty: frame %d begin", frame_index)
		}
		domain.poll_all_terminals(&state)
		if frame_index < 3 {
			logger.linef("src_tty: frame %d polled terminals", frame_index)
		}

		new_width, new_height := tty.size_or_default(80, 24)
		if new_width != surface.width || new_height != surface.height {
			render.destroy_screen_buffer(&surface)
			surface = render.make_screen_buffer(new_width, new_height)
			render.screen_set_background(&surface, config.renderer.background_r, config.renderer.background_g, config.renderer.background_b)
			render.screen_set_foreground(&surface, config.renderer.foreground_r, config.renderer.foreground_g, config.renderer.foreground_b)
			render.screen_set_palette(&surface, config.renderer.palette)
			render.screen_set_bar_colors(&surface, config.renderer.bar)
		}

		if frame_index < 3 {
			logger.linef("src_tty: frame %d render before", frame_index)
		}
		render.render_app(
			&surface,
			&state,
			domain.Rect{x = 0, y = 0, width = surface.width, height = surface.height},
			input_mode,
			false,
			0,
			0,
		)
		if frame_index < 3 {
			logger.linef("src_tty: frame %d render after", frame_index)
		}
		tty.present(&surface)
		if frame_index < 3 {
			logger.linef("src_tty: frame %d present after", frame_index)
		}
		if !logged_first_frame {
			logger.linef("src_tty: first frame presented size=%dx%d", surface.width, surface.height)
			logged_first_frame = true
		}

		frame_index += 1
		if !tty.wait(50) {
			continue
		}

		action := tty.read_input_action(input_mode)
		switch action.kind {
		case .None:
		case .Quit:
			running = false
		case .Command:
			domain.execute_command(&state, action.command)
		case .Pane_Input:
			domain.write_focused_terminal(&state, action.input_data[:action.input_len])
		case .Paste_Clipboard:
			// Clipboard paste is SDL-only.
		case .Enter_Resize_Mode:
			input_mode = .Resize
		case .Exit_Resize_Mode:
			input_mode = .Normal
		}
	}
}
