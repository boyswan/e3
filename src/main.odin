package main

import domain "./app"
import cfg "./config"
import input "./input"
import render "./render"
import renderer "./renderer"
import native "./sdl"
import tty "./tty"
import "base:runtime"
import "core:fmt"
import "core:os"
import sdl3 "vendor:sdl3"

// During a macOS live-resize drag the OS runs a modal tracking loop: SDL
// event polling starves, but SDL still delivers WINDOW_EXPOSED through event
// watches at ~60 FPS. Redraw from the watch so the pane layout tracks the
// window instead of stretching until mouse-up.
Watch_Data :: struct {
	r:      ^renderer.Renderer,
	app:    ^domain.App,
	config: ^cfg.Config,
	mode:   ^input.Input_Mode,
}

watch_data: Watch_Data

resize_watch :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> bool {
	if event == nil {
		return true
	}
	#partial switch event.type {
	case .WINDOW_EXPOSED, .WINDOW_PIXEL_SIZE_CHANGED:
		context = runtime.default_context()
		data := (^Watch_Data)(userdata)
		if data.r != nil {
			render_frame(data.r, data.app, data.config, data.mode^)
		}
	}
	return true
}

render_frame :: proc(r: ^renderer.Renderer, state: ^domain.App, config: ^cfg.Config, mode: input.Input_Mode) {
	domain.poll_all_terminals(state)

	new_width, new_height := renderer.width(r), renderer.height(r)
	if r.kind == .TTY {
		new_width, new_height = tty.size_or_default(80, 24)
	}
	renderer.resize(r, new_width, new_height)

	terminal_width_padding := 0
	terminal_height_padding := 0
	if r.kind == .SDL3 {
		terminal_width_padding = (2 * config.renderer.native_pane_padding_px + renderer.cell_width(r) - 1) / max_int(renderer.cell_width(r), 1)
		terminal_height_padding = (2 * config.renderer.native_pane_padding_px + renderer.cell_height(r) - 1) / max_int(renderer.cell_height(r), 1)
	}

	render.render_app(
		&r.surface,
		state,
		domain.Rect{x = 0, y = 0, width = renderer.width(r), height = renderer.height(r)},
		mode,
		r.kind == .SDL3,
		terminal_width_padding,
		terminal_height_padding,
	)
	renderer.present(r, state, mode)
}

main :: proc() {
	if handle_metadata_args() {
		return
	}

	config_path, config_path_ok := config_path_from_args()
	if !config_path_ok {
		fmt.eprintln("e3: --config/-c requires a file path")
		os.exit(2)
	}
	if config_path != "" && !os.exists(config_path) {
		fmt.eprintln("e3: config file does not exist:", config_path)
		os.exit(2)
	}

	config := cfg.load_config(config_path)
	state: domain.App
	domain.init_app(&state, config.shell_command)
	domain.execute_command(&state, domain.command_open_pane())

	renderer_kind := renderer_kind_from_args()
	width, height := 120, 40
	if renderer_kind == .TTY {
		width, height = tty.size_or_default(80, 24)
	}
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
	if renderer_kind == .SDL3 {
		watch_data = Watch_Data{r = &r, app = &state, config = &config, mode = &input_mode}
		_ = sdl3.AddEventWatch(resize_watch, &watch_data)
		defer sdl3.RemoveEventWatch(resize_watch, &watch_data)
	}

	running := true
	for running {
		render_frame(&r, &state, &config, input_mode)

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

max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

config_path_from_args :: proc() -> (string, bool) {
	for index := 0; index < len(os.args); index += 1 {
		arg := os.args[index]
		if arg == "--config" || arg == "-c" {
			if index + 1 >= len(os.args) {
				return "", false
			}
			return os.args[index + 1], true
		}
		if len(arg) >= len("--config=") && arg[:len("--config=")] == "--config=" {
			path := arg[len("--config="):]
			return path, len(path) > 0
		}
	}
	return "", true
}

renderer_kind_from_args :: proc() -> renderer.Kind {
	for arg in os.args {
		if arg == "--tty" || arg == "--terminal" {
			return .TTY
		}
	}

	return .SDL3
}
