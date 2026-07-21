package renderer

import domain "../app"
import input "../input"
import render "../render"
import native "../sdl"
import tty "../tty"

Kind :: enum {
	TTY,
	SDL3,
}

Renderer :: struct {
	kind:   Kind,
	config: render.Renderer_Config,
	surface: render.Screen_Buffer,

	sdl: native.State,
}

make :: proc(kind: Kind, width: int, height: int, config: ^render.Renderer_Config) -> Renderer {
	sdl_state: native.State
	if kind == .SDL3 {
		sdl_state = native.make_state()
	}

	renderer := Renderer {
		kind = kind,
		config = config^,
		surface = render.make_screen_buffer(width, height),
		sdl = sdl_state,
	}
	apply_surface_theme(&renderer)

	return renderer
}

destroy :: proc(renderer: ^Renderer) {
	if renderer.kind == .SDL3 {
		native.destroy(&renderer.sdl)
	}

	render.destroy_screen_buffer(&renderer.surface)
}

begin :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty.enter_app_screen()
	case .SDL3:
		if native.begin(&renderer.sdl, &renderer.config) {
			width, height := native.surface_size(&renderer.sdl, renderer.surface.width, renderer.surface.height)
			resize(renderer, width, height)
		}
	}
}

end :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty.leave_app_screen()
	case .SDL3:
		native.destroy(&renderer.sdl)
	}
}

resize :: proc(renderer: ^Renderer, width: int, height: int) {
	target_width := width
	target_height := height
	if renderer.kind == .SDL3 {
		target_width, target_height = native.surface_size(&renderer.sdl, renderer.surface.width, renderer.surface.height)
	}

	if target_width == renderer.surface.width && target_height == renderer.surface.height {
		return
	}

	render.destroy_screen_buffer(&renderer.surface)
	renderer.surface = render.make_screen_buffer(target_width, target_height)
	apply_surface_theme(renderer)
}

apply_surface_theme :: proc(renderer: ^Renderer) {
	bg_r, bg_g, bg_b := render.renderer_config_background(renderer.config)
	render.screen_set_background(&renderer.surface, bg_r, bg_g, bg_b)
	fg_r, fg_g, fg_b := render.renderer_config_foreground(renderer.config)
	render.screen_set_foreground(&renderer.surface, fg_r, fg_g, fg_b)
	render.screen_set_palette(&renderer.surface, renderer.config.palette)
	render.screen_set_bar_colors(&renderer.surface, renderer.config.bar)
	render.screen_set_client_colors(&renderer.surface, renderer.config.client)
}

present :: proc(renderer: ^Renderer, state: ^domain.App = nil, mode := input.Input_Mode.Normal) {
	switch renderer.kind {
	case .TTY:
		tty.present(&renderer.surface)
	case .SDL3:
		native.present(&renderer.sdl, &renderer.surface, &renderer.config, state, mode)
	}
}

should_quit :: proc(renderer: ^Renderer) -> bool {
	if renderer.kind != .SDL3 {
		return false
	}

	return native.should_quit()
}

width :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.width
}

height :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.height
}

cell_width :: proc(renderer: ^Renderer) -> int {
	if renderer.kind == .SDL3 {
		return renderer.sdl.cell_width
	}
	return 1
}

cell_height :: proc(renderer: ^Renderer) -> int {
	if renderer.kind == .SDL3 {
		return renderer.sdl.cell_height
	}
	return 1
}

pixel_scale :: proc(renderer: ^Renderer) -> f32 {
	if renderer.kind == .SDL3 {
		return renderer.sdl.pixel_scale
	}
	return 1
}
