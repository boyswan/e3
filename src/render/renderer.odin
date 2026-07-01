package render

import "core:c"
import sdl "vendor:sdl3"

Renderer_Kind :: enum {
	TTY,
	SDL3,
}

Renderer :: struct {
	kind:   Renderer_Kind,
	surface: Screen_Buffer,

	sdl_window:      ^sdl.Window,
	sdl_renderer:    ^sdl.Renderer,
	sdl_initialized: bool,
	cell_width:      int,
	cell_height:     int,
	text_scale:      f32,
}

renderer_make :: proc(kind: Renderer_Kind, width: int, height: int) -> Renderer {
	cell_width := 8
	cell_height := 12
	text_scale: f32 = 1
	if kind == .SDL3 {
		cell_width = 16
		cell_height = 20
		text_scale = 2
	}

	renderer := Renderer {
		kind = kind,
		surface = make_screen_buffer(width, height),
		cell_width = cell_width,
		cell_height = cell_height,
		text_scale = text_scale,
	}

	return renderer
}

renderer_destroy :: proc(renderer: ^Renderer) {
	if renderer.kind == .SDL3 {
		sdl3_destroy(renderer)
	}

	destroy_screen_buffer(&renderer.surface)
}

renderer_begin :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_enter_app_screen()
	case .SDL3:
		sdl3_begin(renderer)
	}
}

renderer_end :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_leave_app_screen()
	case .SDL3:
		sdl3_destroy(renderer)
	}
}

renderer_resize :: proc(renderer: ^Renderer, width: int, height: int) {
	target_width := width
	target_height := height
	if renderer.kind == .SDL3 {
		target_width, target_height = sdl3_surface_size(renderer)
	}

	if target_width == renderer.surface.width && target_height == renderer.surface.height {
		return
	}

	destroy_screen_buffer(&renderer.surface)
	renderer.surface = make_screen_buffer(target_width, target_height)
}

renderer_present :: proc(renderer: ^Renderer) {
	switch renderer.kind {
	case .TTY:
		tty_present(&renderer.surface)
	case .SDL3:
		sdl3_present(renderer)
	}
}

renderer_should_quit :: proc(renderer: ^Renderer) -> bool {
	if renderer.kind != .SDL3 {
		return false
	}

	event: sdl.Event
	for sdl.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			return true
		}
	}

	return false
}

renderer_width :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.width
}

renderer_height :: proc(renderer: ^Renderer) -> int {
	return renderer.surface.height
}

sdl3_begin :: proc(renderer: ^Renderer) {
	if renderer.sdl_renderer != nil {
		return
	}

	if !sdl.Init(sdl.INIT_VIDEO) {
		return
	}
	renderer.sdl_initialized = true

	window: ^sdl.Window
	sdl_renderer: ^sdl.Renderer
	if !sdl.CreateWindowAndRenderer("odin-play", 1000, 700, sdl.WINDOW_RESIZABLE, &window, &sdl_renderer) {
		sdl.Quit()
		renderer.sdl_initialized = false
		return
	}

	renderer.sdl_window = window
	renderer.sdl_renderer = sdl_renderer
	_ = sdl.StartTextInput(window)
	width, height := sdl3_surface_size(renderer)
	renderer_resize(renderer, width, height)
}

sdl3_destroy :: proc(renderer: ^Renderer) {
	if renderer.sdl_window != nil {
		_ = sdl.StopTextInput(renderer.sdl_window)
	}
	if renderer.sdl_renderer != nil {
		sdl.DestroyRenderer(renderer.sdl_renderer)
		renderer.sdl_renderer = nil
	}
	if renderer.sdl_window != nil {
		sdl.DestroyWindow(renderer.sdl_window)
		renderer.sdl_window = nil
	}
	if renderer.sdl_initialized {
		sdl.Quit()
		renderer.sdl_initialized = false
	}
}

sdl3_surface_size :: proc(renderer: ^Renderer) -> (int, int) {
	if renderer.sdl_renderer == nil {
		return renderer.surface.width, renderer.surface.height
	}

	pixel_width: c.int
	pixel_height: c.int
	if !sdl.GetRenderOutputSize(renderer.sdl_renderer, &pixel_width, &pixel_height) {
		return renderer.surface.width, renderer.surface.height
	}

	width := renderer_max_int(int(pixel_width) / renderer.cell_width, 1)
	height := renderer_max_int(int(pixel_height) / renderer.cell_height, 1)
	return width, height
}

sdl3_present :: proc(renderer: ^Renderer) {
	if renderer.sdl_renderer == nil {
		return
	}

	sdl.SetRenderDrawColor(renderer.sdl_renderer, 10, 10, 12, 255)
	sdl.RenderClear(renderer.sdl_renderer)

	for y in 0 ..< renderer.surface.height {
		for x in 0 ..< renderer.surface.width {
			cell := renderer.surface.cells[y * renderer.surface.width + x]
			sdl3_draw_cell(renderer, x, y, cell)
		}
	}

	sdl.RenderPresent(renderer.sdl_renderer)
}

sdl3_draw_cell :: proc(renderer: ^Renderer, x: int, y: int, cell: Cell) {
	fg_r, fg_g, fg_b := sdl3_cell_color(cell.color)
	if cell.bold {
		fg_r = renderer_min_int(fg_r + 40, 255)
		fg_g = renderer_min_int(fg_g + 40, 255)
		fg_b = renderer_min_int(fg_b + 40, 255)
	}

	if cell.color != .Default {
		rect := sdl.FRect {
			x = f32(x * renderer.cell_width),
			y = f32(y * renderer.cell_height),
			w = f32(renderer.cell_width),
			h = f32(renderer.cell_height),
		}
		sdl.SetRenderDrawColor(renderer.sdl_renderer, 24, 24, 30, 255)
		sdl.RenderFillRect(renderer.sdl_renderer, &rect)
	}

	if cell.line_mask != 0 {
		sdl3_draw_line_cell(renderer, x, y, fg_r, fg_g, fg_b)
		return
	}

	if cell.glyph == " " {
		return
	}

	sdl.SetRenderDrawColor(renderer.sdl_renderer, u8(fg_r), u8(fg_g), u8(fg_b), 255)
	_ = sdl.SetRenderScale(renderer.sdl_renderer, renderer.text_scale, renderer.text_scale)

	buf: [8]u8
	glyph_len := renderer_min_int(len(cell.glyph), len(buf) - 1)
	for index in 0 ..< glyph_len {
		buf[index] = cell.glyph[index]
	}
	buf[glyph_len] = 0

	text_x := f32(x * renderer.cell_width) / renderer.text_scale
	text_y := f32(y * renderer.cell_height + 2) / renderer.text_scale
	sdl.RenderDebugText(renderer.sdl_renderer, text_x, text_y, cstring(&buf[0]))
	_ = sdl.SetRenderScale(renderer.sdl_renderer, 1, 1)
}

sdl3_draw_line_cell :: proc(renderer: ^Renderer, x: int, y: int, r: int, g: int, b: int) {
	cell_x := f32(x * renderer.cell_width)
	cell_y := f32(y * renderer.cell_height)
	center_x := cell_x + f32(renderer.cell_width / 2)
	center_y := cell_y + f32(renderer.cell_height / 2)
	line_width: f32 = 1
	half_line := line_width / 2

	sdl.SetRenderDrawColor(renderer.sdl_renderer, u8(r), u8(g), u8(b), 255)

	if renderer.surface.cells[y * renderer.surface.width + x].line_mask & LINE_LEFT != 0 {
		rect := sdl.FRect{x = cell_x, y = center_y - half_line, w = center_x - cell_x, h = line_width}
		sdl.RenderFillRect(renderer.sdl_renderer, &rect)
	}
	if renderer.surface.cells[y * renderer.surface.width + x].line_mask & LINE_RIGHT != 0 {
		rect := sdl.FRect{x = center_x, y = center_y - half_line, w = cell_x + f32(renderer.cell_width) - center_x, h = line_width}
		sdl.RenderFillRect(renderer.sdl_renderer, &rect)
	}
	if renderer.surface.cells[y * renderer.surface.width + x].line_mask & LINE_UP != 0 {
		rect := sdl.FRect{x = center_x - half_line, y = cell_y, w = line_width, h = center_y - cell_y}
		sdl.RenderFillRect(renderer.sdl_renderer, &rect)
	}
	if renderer.surface.cells[y * renderer.surface.width + x].line_mask & LINE_DOWN != 0 {
		rect := sdl.FRect{x = center_x - half_line, y = center_y, w = line_width, h = cell_y + f32(renderer.cell_height) - center_y}
		sdl.RenderFillRect(renderer.sdl_renderer, &rect)
	}
}

sdl3_cell_color :: proc(color: Cell_Color) -> (int, int, int) {
	switch color {
	case .Default:
		return 220, 220, 220
	case .Focused:
		return 0, 220, 255
	case .Split_Hint:
		return 255, 0, 220
	}

	return 220, 220, 220
}

renderer_min_int :: proc(a: int, b: int) -> int {
	if a < b {
		return a
	}
	return b
}

renderer_max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}
	return b
}
