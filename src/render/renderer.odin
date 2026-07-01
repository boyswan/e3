package render

Renderer_Kind :: enum {
	TTY,
	SDL3,
}

Renderer :: struct {
	kind:   Renderer_Kind,
	surface: Screen_Buffer,
}

renderer_make :: proc(kind: Renderer_Kind, width: int, height: int) -> Renderer {
	return Renderer {
		kind = kind,
		surface = make_screen_buffer(width, height),
	}
}

renderer_destroy :: proc(renderer: ^Renderer) {
	destroy_screen_buffer(&renderer.surface)
}

renderer_begin :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_enter_app_screen()
	case .SDL3:
		// Native backend will initialize SDL3 here.
	}
}

renderer_end :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_leave_app_screen()
	case .SDL3:
		// Native backend will shut down SDL3 here.
	}
}

renderer_resize :: proc(renderer: ^Renderer, width: int, height: int) {
	if width == renderer.surface.width && height == renderer.surface.height {
		return
	}

	destroy_screen_buffer(&renderer.surface)
	renderer.surface = make_screen_buffer(width, height)
}

renderer_present :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_present(&renderer.surface)
	case .SDL3:
		// Native backend will draw the surface via SDL3 here.
	}
}

renderer_width :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.width
}

renderer_height :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.height
}
