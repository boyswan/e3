package renderer

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

make :: proc(kind: Kind, width: int, height: int, config: render.Renderer_Config) -> Renderer {
	sdl_state: native.State
	if kind == .SDL3 {
		sdl_state = native.make_state()
	}

	renderer := Renderer {
		kind = kind,
		config = config,
		surface = render.make_screen_buffer(width, height),
		sdl = sdl_state,
	}
	apply_surface_background(&renderer)

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
		if native.begin(&renderer.sdl, renderer.config) {
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
	apply_surface_background(renderer)
}

apply_surface_background :: proc(renderer: ^Renderer) {
	r, g, b := render.renderer_config_background(renderer.config)
	render.screen_set_background(&renderer.surface, r, g, b)
}

present :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty.present(&renderer.surface)
	case .SDL3:
		native.present(&renderer.sdl, &renderer.surface, renderer.config)
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
