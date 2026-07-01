package sdl

import "core:c"
import "core:os"
import "core:strings"
import input "../input"
import render "../render"
import sdl3 "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Glyph_Texture :: struct {
	rune:    u32,
	r:       u8,
	g:       u8,
	b:       u8,
	bg_r:    u8,
	bg_g:    u8,
	bg_b:    u8,
	texture: ^sdl3.Texture,
	width:   f32,
	height:  f32,
}

State :: struct {
	window:          ^sdl3.Window,
	renderer:        ^sdl3.Renderer,
	initialized:     bool,
	ttf_initialized: bool,
	font:            ^ttf.Font,
	font_ascent:     int,
	font_height:     int,
	glyph_cache:     [dynamic]Glyph_Texture,
	cell_width:      int,
	cell_height:     int,
	text_scale:      f32,

	selecting:       bool,
	selection_valid: bool,
	selection_start_x: int,
	selection_start_y: int,
	selection_end_x:   int,
	selection_end_y:   int,
}

make_state :: proc() -> State {
	return State {
		glyph_cache = make([dynamic]Glyph_Texture),
		cell_width = 11,
		cell_height = 22,
		text_scale = 1,
	}
}

begin :: proc(state: ^State, config: render.Renderer_Config) -> bool {
	if state.renderer != nil {
		return true
	}

	if !sdl3.Init(sdl3.INIT_VIDEO) {
		return false
	}
	state.initialized = true

	window: ^sdl3.Window
	sdl_renderer: ^sdl3.Renderer
	window_flags := sdl3.WindowFlags{.RESIZABLE}
	if !sdl3.CreateWindowAndRenderer("odin-play", 1000, 700, window_flags, &window, &sdl_renderer) {
		sdl3.Quit()
		state.initialized = false
		return false
	}

	state.window = window
	state.renderer = sdl_renderer
	init_font(state, config)
	_ = sdl3.StartTextInput(window)
	return true
}

destroy :: proc(state: ^State) {
	destroy_glyph_cache(state)
	if state.font != nil {
		ttf.CloseFont(state.font)
		state.font = nil
	}
	if state.ttf_initialized {
		ttf.Quit()
		state.ttf_initialized = false
	}
	if state.window != nil {
		_ = sdl3.StopTextInput(state.window)
	}
	if state.renderer != nil {
		sdl3.DestroyRenderer(state.renderer)
		state.renderer = nil
	}
	if state.window != nil {
		sdl3.DestroyWindow(state.window)
		state.window = nil
	}
	if state.initialized {
		sdl3.Quit()
		state.initialized = false
	}
}

destroy_glyph_cache :: proc(state: ^State) {
	for &entry in state.glyph_cache {
		if entry.texture != nil {
			sdl3.DestroyTexture(entry.texture)
			entry.texture = nil
		}
	}
	clear(&state.glyph_cache)
}

surface_size :: proc(state: ^State, current_width: int, current_height: int) -> (int, int) {
	if state.renderer == nil {
		return current_width, current_height
	}

	pixel_width: c.int
	pixel_height: c.int
	if !sdl3.GetRenderOutputSize(state.renderer, &pixel_width, &pixel_height) {
		return current_width, current_height
	}

	width := max_int(int(pixel_width) / state.cell_width, 1)
	height := max_int(int(pixel_height) / state.cell_height, 1)
	return width, height
}

should_quit :: proc() -> bool {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			return true
		}
	}

	return false
}

present :: proc(state: ^State, surface: ^render.Screen_Buffer, config: render.Renderer_Config) {
	if state.renderer == nil {
		return
	}

	bg_r, bg_g, bg_b := render.renderer_config_background(config)
	_ = sdl3.SetRenderDrawBlendMode(state.renderer, sdl3.BLENDMODE_NONE)
	sdl3.SetRenderDrawColor(state.renderer, bg_r, bg_g, bg_b, 255)
	sdl3.RenderClear(state.renderer)

	output_width: c.int
	output_height: c.int
	if sdl3.GetRenderOutputSize(state.renderer, &output_width, &output_height) {
		background := sdl3.FRect{x = 0, y = 0, w = f32(output_width), h = f32(output_height)}
		sdl3.RenderFillRect(state.renderer, &background)
	} else {
		sdl3.RenderFillRect(state.renderer, nil)
	}

	for y in 0 ..< surface.height {
		for x in 0 ..< surface.width {
			cell := surface.cells[y * surface.width + x]
			if selection_contains(state, x, y) {
				apply_selection_style(state, surface, &cell)
			}
			draw_cell(state, surface, x, y, cell)
		}
	}

	sdl3.RenderPresent(state.renderer)
}

selection_contains :: proc(state: ^State, x: int, y: int) -> bool {
	if !state.selection_valid {
		return false
	}

	start_x, start_y, end_x, end_y := normalized_selection(state)
	if y < start_y || y > end_y {
		return false
	}
	if start_y == end_y {
		return x >= start_x && x <= end_x
	}
	if y == start_y {
		return x >= start_x
	}
	if y == end_y {
		return x <= end_x
	}
	return true
}

normalized_selection :: proc(state: ^State) -> (int, int, int, int) {
	start_x := state.selection_start_x
	start_y := state.selection_start_y
	end_x := state.selection_end_x
	end_y := state.selection_end_y

	if start_y > end_y || (start_y == end_y && start_x > end_x) {
		return end_x, end_y, start_x, start_y
	}
	return start_x, start_y, end_x, end_y
}

apply_selection_style :: proc(state: ^State, surface: ^render.Screen_Buffer, cell: ^render.Cell) {
	bg := surface.palette[4]
	fg := surface.palette[0]
	cell.fg_set = true
	cell.fg_r = fg.r
	cell.fg_g = fg.g
	cell.fg_b = fg.b
	cell.bg_set = true
	cell.bg_r = bg.r
	cell.bg_g = bg.g
	cell.bg_b = bg.b
}

draw_cell :: proc(state: ^State, surface: ^render.Screen_Buffer, x: int, y: int, cell: render.Cell) {
	fg_r, fg_g, fg_b := cell_color(surface, cell)
	if cell.bold && !cell.fg_set {
		fg_r = min_int(fg_r + 40, 255)
		fg_g = min_int(fg_g + 40, 255)
		fg_b = min_int(fg_b + 40, 255)
	}

	bg_r, bg_g, bg_b := cell_background(surface, cell)
	rect := sdl3.FRect {
		x = f32(x * state.cell_width),
		y = f32(y * state.cell_height),
		w = f32(state.cell_width),
		h = f32(state.cell_height),
	}
	sdl3.SetRenderDrawColor(state.renderer, u8(bg_r), u8(bg_g), u8(bg_b), 255)
	sdl3.RenderFillRect(state.renderer, &rect)

	if cell.line_mask != 0 {
		draw_line_cell(state, surface, x, y, fg_r, fg_g, fg_b)
		return
	}

	if state.font != nil {
		draw_font_cell(state, x, y, cell, fg_r, fg_g, fg_b, bg_r, bg_g, bg_b)
		return
	}

	buf: [8]u8
	glyph_len := cell_text(cell, buf[:])
	if glyph_len == 0 {
		return
	}
	buf[glyph_len] = 0

	sdl3.SetRenderDrawColor(state.renderer, u8(fg_r), u8(fg_g), u8(fg_b), 255)
	_ = sdl3.SetRenderScale(state.renderer, state.text_scale, state.text_scale)

	text_x := f32(x * state.cell_width) / state.text_scale
	text_y := f32(y * state.cell_height + 2) / state.text_scale
	sdl3.RenderDebugText(state.renderer, text_x, text_y, cstring(&buf[0]))
	_ = sdl3.SetRenderScale(state.renderer, 1, 1)
}

init_font :: proc(state: ^State, config: render.Renderer_Config) {
	if !ttf.Init() {
		return
	}
	state.ttf_initialized = true

	font_path := resolve_font_path(config)
	if font_path == "" {
		return
	}

	font_path_c := strings.clone_to_cstring(font_path, context.temp_allocator)
	state.font = ttf.OpenFont(font_path_c, config.font_size)
	if state.font != nil {
		ttf.SetFontHinting(state.font, .MONO)
		state.font_ascent = int(ttf.GetFontAscent(state.font))
		state.font_height = int(ttf.GetFontHeight(state.font))

		minx, maxx, miny, maxy, advance: c.int
		if ttf.GetGlyphMetrics(state.font, 'M', &minx, &maxx, &miny, &maxy, &advance) {
			state.cell_width = max_int(int(advance), 1)
		}
		if state.font_height > 0 {
			state.cell_height = state.font_height
		}
	}
}

resolve_font_path :: proc(config: render.Renderer_Config) -> string {
	if config.font_path != "" {
		return config.font_path
	}

	font_family := config.font_family
	if font_family == "" {
		font_family = "monospace"
	}

	state, stdout, stderr, err := os.process_exec(os.Process_Desc {
		command = []string{"fc-match", "-f", "%{file}", font_family},
	}, context.temp_allocator)
	_ = stderr
	if err == nil && state.success && len(stdout) > 0 {
		path := strings.trim_space(string(stdout))
		if path != "" {
			return path
		}
	}

	return ""
}

draw_font_cell :: proc(state: ^State, x: int, y: int, cell: render.Cell, fg_r: int, fg_g: int, fg_b: int, bg_r: int, bg_g: int, bg_b: int) {
	rune := cell_rune(cell)
	if rune == 0 || rune == ' ' {
		return
	}

	entry := get_glyph_texture(state, rune, u8(fg_r), u8(fg_g), u8(fg_b), u8(bg_r), u8(bg_g), u8(bg_b))
	if entry == nil || entry.texture == nil {
		return
	}

	dst := sdl3.FRect {
		x = f32(x * state.cell_width),
		y = f32(y * state.cell_height),
		w = entry.width,
		h = entry.height,
	}
	sdl3.RenderTexture(state.renderer, entry.texture, nil, &dst)
}

cell_rune :: proc(cell: render.Cell) -> u32 {
	if cell.rune != 0 {
		return cell.rune
	}
	if len(cell.glyph) == 1 {
		return u32(cell.glyph[0])
	}
	return 0
}

get_glyph_texture :: proc(state: ^State, rune: u32, r: u8, g: u8, b: u8, bg_r: u8, bg_g: u8, bg_b: u8) -> ^Glyph_Texture {
	for index in 0 ..< len(state.glyph_cache) {
		entry := &state.glyph_cache[index]
		if entry.rune == rune && entry.r == r && entry.g == g && entry.b == b && entry.bg_r == bg_r && entry.bg_g == bg_g && entry.bg_b == bg_b {
			return entry
		}
	}

	text: [8]u8
	text_len := encode_utf8(rune, text[:len(text) - 1])
	if text_len == 0 {
		return nil
	}
	text[text_len] = 0

	fg := sdl3.Color{r, g, b, 255}
	bg := sdl3.Color{bg_r, bg_g, bg_b, 255}
	surface := ttf.RenderText_LCD(state.font, cstring(&text[0]), c.size_t(text_len), fg, bg)
	if surface == nil {
		return nil
	}
	defer sdl3.DestroySurface(surface)

	texture := sdl3.CreateTextureFromSurface(state.renderer, surface)
	if texture == nil {
		return nil
	}
	_ = sdl3.SetTextureBlendMode(texture, sdl3.BLENDMODE_BLEND)

	texture_width: f32
	texture_height: f32
	if !sdl3.GetTextureSize(texture, &texture_width, &texture_height) {
		sdl3.DestroyTexture(texture)
		return nil
	}

	append(&state.glyph_cache, Glyph_Texture {
		rune = rune,
		r = r,
		g = g,
		b = b,
		bg_r = bg_r,
		bg_g = bg_g,
		bg_b = bg_b,
		texture = texture,
		width = texture_width,
		height = texture_height,
	})

	return &state.glyph_cache[len(state.glyph_cache) - 1]
}

cell_text :: proc(cell: render.Cell, buffer: []u8) -> int {
	if len(buffer) == 0 {
		return 0
	}

	if cell.rune != 0 {
		return encode_utf8(cell.rune, buffer[:len(buffer) - 1])
	}

	if cell.glyph == " " {
		return 0
	}

	glyph_len := min_int(len(cell.glyph), len(buffer) - 1)
	for index in 0 ..< glyph_len {
		buffer[index] = cell.glyph[index]
	}
	return glyph_len
}

encode_utf8 :: proc(value: u32, buffer: []u8) -> int {
	if value <= 0x7f {
		if len(buffer) < 1 { return 0 }
		buffer[0] = u8(value)
		return 1
	}
	if value <= 0x7ff {
		if len(buffer) < 2 { return 0 }
		buffer[0] = 0xc0 | u8(value >> 6)
		buffer[1] = 0x80 | u8(value & 0x3f)
		return 2
	}
	if value <= 0xffff {
		if len(buffer) < 3 { return 0 }
		buffer[0] = 0xe0 | u8(value >> 12)
		buffer[1] = 0x80 | u8((value >> 6) & 0x3f)
		buffer[2] = 0x80 | u8(value & 0x3f)
		return 3
	}
	if value <= 0x10ffff {
		if len(buffer) < 4 { return 0 }
		buffer[0] = 0xf0 | u8(value >> 18)
		buffer[1] = 0x80 | u8((value >> 12) & 0x3f)
		buffer[2] = 0x80 | u8((value >> 6) & 0x3f)
		buffer[3] = 0x80 | u8(value & 0x3f)
		return 4
	}
	return 0
}

draw_line_cell :: proc(state: ^State, surface: ^render.Screen_Buffer, x: int, y: int, r: int, g: int, b: int) {
	cell_x := f32(x * state.cell_width)
	cell_y := f32(y * state.cell_height)
	center_x := cell_x + f32(state.cell_width / 2)
	center_y := cell_y + f32(state.cell_height / 2)
	line_width: f32 = 1
	half_line := line_width / 2

	sdl3.SetRenderDrawColor(state.renderer, u8(r), u8(g), u8(b), 255)

	cell := surface.cells[y * surface.width + x]
	if cell.line_mask & render.LINE_LEFT != 0 {
		rect := sdl3.FRect{x = cell_x, y = center_y - half_line, w = center_x - cell_x, h = line_width}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if cell.line_mask & render.LINE_RIGHT != 0 {
		rect := sdl3.FRect{x = center_x, y = center_y - half_line, w = cell_x + f32(state.cell_width) - center_x, h = line_width}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if cell.line_mask & render.LINE_UP != 0 {
		rect := sdl3.FRect{x = center_x - half_line, y = cell_y, w = line_width, h = center_y - cell_y}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if cell.line_mask & render.LINE_DOWN != 0 {
		rect := sdl3.FRect{x = center_x - half_line, y = center_y, w = line_width, h = cell_y + f32(state.cell_height) - center_y}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
}

cell_color :: proc(surface: ^render.Screen_Buffer, cell: render.Cell) -> (int, int, int) {
	switch cell.color {
	case .Default:
		if cell.fg_set {
			return int(cell.fg_r), int(cell.fg_g), int(cell.fg_b)
		}
		return int(surface.foreground_r), int(surface.foreground_g), int(surface.foreground_b)
	case .Inactive:
		return int(surface.palette[8].r), int(surface.palette[8].g), int(surface.palette[8].b)
	case .Focused_Inactive:
		return int(surface.palette[7].r), int(surface.palette[7].g), int(surface.palette[7].b)
	case .Focused:
		return int(surface.palette[4].r), int(surface.palette[4].g), int(surface.palette[4].b)
	case .Split_Hint:
		return int(surface.palette[13].r), int(surface.palette[13].g), int(surface.palette[13].b)
	}

	return int(surface.foreground_r), int(surface.foreground_g), int(surface.foreground_b)
}

cell_background :: proc(surface: ^render.Screen_Buffer, cell: render.Cell) -> (int, int, int) {
	if cell.bg_set {
		return int(cell.bg_r), int(cell.bg_g), int(cell.bg_b)
	}
	return int(surface.background_r), int(surface.background_g), int(surface.background_b)
}

min_int :: proc(a: int, b: int) -> int {
	if a < b {
		return a
	}
	return b
}

max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}
	return b
}
