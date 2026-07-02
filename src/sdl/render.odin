package sdl

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import logger "../debuglog"
import domain "../app"
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
	native_border_px: int,
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
	logger.line("sdl: begin")
	if state.renderer != nil {
		logger.line("sdl: begin already initialized")
		return true
	}

	logger.line("sdl: Init")
	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fmt.eprintln("e3: SDL_Init failed:", sdl3.GetError())
		return false
	}
	state.initialized = true
	logger.line("sdl: Init ok")

	window: ^sdl3.Window
	sdl_renderer: ^sdl3.Renderer
	window_flags := sdl3.WindowFlags{.RESIZABLE}
	logger.line("sdl: CreateWindowAndRenderer")
	if !sdl3.CreateWindowAndRenderer("e3", 1000, 700, window_flags, &window, &sdl_renderer) {
		fmt.eprintln("e3: SDL_CreateWindowAndRenderer failed:", sdl3.GetError())
		sdl3.Quit()
		state.initialized = false
		return false
	}

	state.window = window
	state.renderer = sdl_renderer
	state.native_border_px = config.native_pane_border_px
	logger.line("sdl: window/renderer ok")
	init_font(state, config)
	logger.linef("sdl: font init complete font=%p cell=%dx%d", state.font, state.cell_width, state.cell_height)
	_ = sdl3.StartTextInput(window)
	logger.line("sdl: begin ok")
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

present_frame_logged := false

present :: proc(state: ^State, surface: ^render.Screen_Buffer, config: render.Renderer_Config, app: ^domain.App = nil, mode := input.Input_Mode.Normal) {
	if state.renderer == nil {
		logger.line("sdl: present skipped nil renderer")
		return
	}
	if !present_frame_logged {
		logger.linef("sdl: first present surface=%dx%d cell=%dx%d font=%p", surface.width, surface.height, state.cell_width, state.cell_height, state.font)
		present_frame_logged = true
	}

	bg_r, bg_g, bg_b := render.renderer_config_background(config)
	_ = sdl3.SetRenderDrawBlendMode(state.renderer, sdl3.BLENDMODE_NONE)
	sdl3.SetRenderDrawColor(state.renderer, bg_r, bg_g, bg_b, 255)
	sdl3.RenderClear(state.renderer)

	output_width: c.int
	output_height: c.int
	output_pixel_width := 0
	output_pixel_height := 0
	if sdl3.GetRenderOutputSize(state.renderer, &output_width, &output_height) {
		output_pixel_width = int(output_width)
		output_pixel_height = int(output_height)
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

			offset_x, offset_y := native_cell_offset(state, config, app, x, y)
			draw_cell_background(state, surface, x, y, cell, offset_x, offset_y, output_pixel_height)
		}
	}

	for y in 0 ..< surface.height {
		for x in 0 ..< surface.width {
			cell := surface.cells[y * surface.width + x]
			if selection_contains(state, x, y) {
				apply_selection_style(state, surface, &cell)
			}

			offset_x, offset_y := native_cell_offset(state, config, app, x, y)
			draw_cell_foreground(state, surface, x, y, cell, offset_x, offset_y, output_pixel_height)
		}
	}

	when ODIN_OS != .Darwin {
		if app != nil {
			draw_native_chrome(state, surface, app, mode, output_pixel_width, output_pixel_height)
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

native_cell_offset :: proc(state: ^State, config: render.Renderer_Config, app: ^domain.App, x: int, y: int) -> (int, int) {
	if app != nil && config.native_pane_padding_px > 0 {
		_, ok := native_cell_pane_bounds(app, x, y)
		if ok {
			content_inset := max_int(config.native_pane_padding_px + state.native_border_px, 0)
			return content_inset, content_inset
		}
	}
	return 0, 0
}

draw_cell_y :: proc(state: ^State, surface: ^render.Screen_Buffer, y: int, output_pixel_height := 0) -> int {
	cell_y := y * state.cell_height
	if output_pixel_height > 0 && y == surface.height - 1 {
		cell_y = max_int(output_pixel_height - state.cell_height, 0)
	}
	return cell_y
}

draw_cell_background :: proc(state: ^State, surface: ^render.Screen_Buffer, x: int, y: int, cell: render.Cell, offset_x := 0, offset_y := 0, output_pixel_height := 0) {
	bg_r, bg_g, bg_b := cell_background(surface, cell)
	cell_y := draw_cell_y(state, surface, y, output_pixel_height)
	rect := sdl3.FRect {
		x = f32(x * state.cell_width + offset_x),
		y = f32(cell_y + offset_y),
		w = f32(state.cell_width),
		h = f32(state.cell_height),
	}
	sdl3.SetRenderDrawColor(state.renderer, u8(bg_r), u8(bg_g), u8(bg_b), 255)
	sdl3.RenderFillRect(state.renderer, &rect)
}

draw_cell_foreground :: proc(state: ^State, surface: ^render.Screen_Buffer, x: int, y: int, cell: render.Cell, offset_x := 0, offset_y := 0, output_pixel_height := 0) {
	fg_r, fg_g, fg_b := cell_color(surface, cell)
	if cell.bold && !cell.fg_set {
		fg_r = min_int(fg_r + 40, 255)
		fg_g = min_int(fg_g + 40, 255)
		fg_b = min_int(fg_b + 40, 255)
	}
	bg_r, bg_g, bg_b := cell_background(surface, cell)
	cell_y := draw_cell_y(state, surface, y, output_pixel_height)

	line_mask := cell.line_mask
	if line_mask == 0 {
		line_mask = box_drawing_line_mask(cell_rune(cell))
	}
	if line_mask != 0 {
		draw_line_mask_cell(state, surface, x, y, line_mask, fg_r, fg_g, fg_b, offset_x, offset_y, output_pixel_height)
		return
	}

	if state.font != nil && draw_font_cell(state, x, cell_y, cell, fg_r, fg_g, fg_b, bg_r, bg_g, bg_b, offset_x, offset_y) {
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

	text_x := f32(x * state.cell_width + offset_x) / state.text_scale
	text_y := f32(cell_y + 2 + offset_y) / state.text_scale
	sdl3.RenderDebugText(state.renderer, text_x, text_y, cstring(&buf[0]))
	_ = sdl3.SetRenderScale(state.renderer, 1, 1)
}

init_font :: proc(state: ^State, config: render.Renderer_Config) {
	logger.line("sdl: TTF_Init")
	if !ttf.Init() {
		fmt.eprintln("e3: TTF_Init failed:", sdl3.GetError())
		return
	}
	state.ttf_initialized = true
	logger.line("sdl: TTF_Init ok")

	font_path := resolve_font_path(config)
	logger.linef("sdl: resolved font path=%s", font_path)
	if font_path != "" && open_font_path(state, font_path, config.font_size) {
		return
	}

	if font_path == "" {
		fmt.eprintln("e3: could not resolve font family:", config.font_family)
	} else {
		fmt.eprintln("e3: failed to open font:", font_path, sdl3.GetError())
	}

	for fallback_index in 0 ..< fallback_font_family_count() {
		fallback_family := fallback_font_family(fallback_index)
		fallback_path := resolve_font_path_for_family(fallback_family)
		if fallback_path != "" && open_font_path(state, fallback_path, config.font_size) {
			fmt.eprintln("e3: using fallback font:", fallback_family)
			return
		}
	}

	fmt.eprintln("e3: no usable TTF font found; falling back to SDL debug text")
}

open_font_path :: proc(state: ^State, font_path: string, font_size: f32) -> bool {
	logger.linef("sdl: opening font %s size=%f", font_path, font_size)
	font_path_c := strings.clone_to_cstring(font_path, context.temp_allocator)
	state.font = ttf.OpenFont(font_path_c, font_size)
	if state.font == nil {
		logger.linef("sdl: OpenFont failed %s", sdl3.GetError())
		return false
	}

	ttf.SetFontHinting(state.font, .MONO)
	state.font_ascent = int(ttf.GetFontAscent(state.font))
	state.font_height = int(ttf.GetFontHeight(state.font))

	minx, maxx, miny, maxy, advance: c.int
	if ttf.GetGlyphMetrics(state.font, 'M', &minx, &maxx, &miny, &maxy, &advance) && advance >= 4 {
		state.cell_width = int(advance)
	}
	if state.font_height >= 8 {
		state.cell_height = state.font_height
	}
	logger.linef("sdl: OpenFont ok metrics ascent=%d height=%d advance=%d cell=%dx%d", state.font_ascent, state.font_height, advance, state.cell_width, state.cell_height)
	return true
}

resolve_font_path :: proc(config: render.Renderer_Config) -> string {
	if config.font_path != "" {
		return config.font_path
	}

	font_family := config.font_family
	if font_family == "" {
		font_family = "monospace"
	}

	return resolve_font_path_for_family(font_family)
}

resolve_font_path_for_family :: proc(font_family: string) -> string {
	path := resolve_font_path_with_system(font_family)
	if path != "" {
		return path
	}

	state, stdout, stderr, err := os.process_exec(os.Process_Desc {
		command = []string{"fc-match", "-f", "%{file}", font_family},
	}, context.temp_allocator)
	_ = stderr
	if err == nil && state.success && len(stdout) > 0 {
		path = strings.trim_space(string(stdout))
		if path != "" {
			return path
		}
	}

	return ""
}

when ODIN_OS == .Darwin {
	fallback_font_family_count :: proc() -> int {
		return 3
	}

	fallback_font_family :: proc(index: int) -> string {
		switch index {
		case 0:
			return "Menlo"
		case 1:
			return "Monaco"
		case 2:
			return "Courier New"
		}
		return "Menlo"
	}
} else {
	fallback_font_family_count :: proc() -> int {
		return 1
	}

	fallback_font_family :: proc(index: int) -> string {
		return "monospace"
	}
}

when ODIN_OS == .Darwin {
	foreign import corefoundation "system:CoreFoundation.framework"
	foreign import coretext "system:CoreText.framework"

	CFTypeRef :: rawptr
	CFStringRef :: rawptr
	CFURLRef :: rawptr
	CTFontRef :: rawptr

	kCFStringEncodingUTF8 :: u32(0x08000100)

	foreign corefoundation {
		CFStringCreateWithCString :: proc(alloc: rawptr, c_str: cstring, encoding: u32) -> CFStringRef ---
		CFRelease :: proc(value: CFTypeRef) ---
		CFURLGetFileSystemRepresentation :: proc(url: CFURLRef, resolve_against_base: u8, buffer: [^]u8, max_buffer_len: c.long) -> u8 ---
	}

	foreign coretext {
		CTFontCreateWithName :: proc(name: CFStringRef, size: f64, matrix_ptr: rawptr) -> CTFontRef ---
		CTFontCopyAttribute :: proc(font: CTFontRef, attribute: CFStringRef) -> CFTypeRef ---
	}

	resolve_font_path_with_system :: proc(font_family: string) -> string {
		font_name_c := strings.clone_to_cstring(font_family, context.temp_allocator)
		font_name := CFStringCreateWithCString(nil, font_name_c, kCFStringEncodingUTF8)
		if font_name == nil {
			return ""
		}
		defer CFRelease(font_name)

		font := CTFontCreateWithName(font_name, 12, nil)
		if font == nil {
			return ""
		}
		defer CFRelease(font)

		url_attribute := CFStringCreateWithCString(nil, "NSFontURLAttribute", kCFStringEncodingUTF8)
		if url_attribute == nil {
			return ""
		}
		defer CFRelease(url_attribute)

		url := CFURLRef(CTFontCopyAttribute(font, url_attribute))
		if url == nil {
			return ""
		}
		defer CFRelease(url)

		buffer: [4096]u8
		if CFURLGetFileSystemRepresentation(url, 1, &buffer[0], c.long(len(buffer))) == 0 {
			return ""
		}

		path_len := 0
		for path_len < len(buffer) && buffer[path_len] != 0 {
			path_len += 1
		}
		if path_len == 0 {
			return ""
		}

		return strings.clone(string(buffer[:path_len]), context.temp_allocator)
	}
} else {
	resolve_font_path_with_system :: proc(font_family: string) -> string {
		return ""
	}
}

draw_font_cell :: proc(state: ^State, x: int, cell_y: int, cell: render.Cell, fg_r: int, fg_g: int, fg_b: int, bg_r: int, bg_g: int, bg_b: int, offset_x := 0, offset_y := 0) -> bool {
	rune := cell_rune(cell)
	if rune == 0 || rune == ' ' {
		return true
	}

	entry := get_glyph_texture(state, rune, u8(fg_r), u8(fg_g), u8(fg_b), u8(bg_r), u8(bg_g), u8(bg_b))
	if entry == nil || entry.texture == nil {
		return false
	}

	dst := sdl3.FRect {
		x = f32(x * state.cell_width + offset_x),
		y = f32(cell_y + offset_y),
		w = entry.width,
		h = entry.height,
	}
	sdl3.RenderTexture(state.renderer, entry.texture, nil, &dst)
	return true
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
	_ = bg
	surface := ttf.RenderText_Blended(state.font, cstring(&text[0]), c.size_t(text_len), fg)
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

draw_line_mask_cell :: proc(state: ^State, surface: ^render.Screen_Buffer, x: int, y: int, line_mask: u8, r: int, g: int, b: int, offset_x := 0, offset_y := 0, output_pixel_height := 0) {
	cell_x := f32(x * state.cell_width + offset_x)
	cell_y := f32(draw_cell_y(state, surface, y, output_pixel_height) + offset_y)
	center_x := cell_x + f32(state.cell_width / 2)
	center_y := cell_y + f32(state.cell_height / 2)
	line_width: f32 = 1
	half_line := line_width / 2

	sdl3.SetRenderDrawColor(state.renderer, u8(r), u8(g), u8(b), 255)

	if line_mask & render.LINE_LEFT != 0 {
		rect := sdl3.FRect{x = cell_x, y = center_y - half_line, w = center_x - cell_x, h = line_width}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if line_mask & render.LINE_RIGHT != 0 {
		rect := sdl3.FRect{x = center_x, y = center_y - half_line, w = cell_x + f32(state.cell_width) - center_x, h = line_width}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if line_mask & render.LINE_UP != 0 {
		rect := sdl3.FRect{x = center_x - half_line, y = cell_y, w = line_width, h = center_y - cell_y}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
	if line_mask & render.LINE_DOWN != 0 {
		rect := sdl3.FRect{x = center_x - half_line, y = center_y, w = line_width, h = cell_y + f32(state.cell_height) - center_y}
		sdl3.RenderFillRect(state.renderer, &rect)
	}
}

box_drawing_line_mask :: proc(rune: u32) -> u8 {
	switch rune {
	case '│', '┃', '║':
		return render.LINE_UP | render.LINE_DOWN
	case '─', '━', '═':
		return render.LINE_LEFT | render.LINE_RIGHT
	case '┌', '╭', '╔':
		return render.LINE_RIGHT | render.LINE_DOWN
	case '┐', '╮', '╗':
		return render.LINE_LEFT | render.LINE_DOWN
	case '└', '╰', '╚':
		return render.LINE_RIGHT | render.LINE_UP
	case '┘', '╯', '╝':
		return render.LINE_LEFT | render.LINE_UP
	case '├', '┣', '╠':
		return render.LINE_UP | render.LINE_DOWN | render.LINE_RIGHT
	case '┤', '┫', '╣':
		return render.LINE_UP | render.LINE_DOWN | render.LINE_LEFT
	case '┬', '┳', '╦':
		return render.LINE_LEFT | render.LINE_RIGHT | render.LINE_DOWN
	case '┴', '┻', '╩':
		return render.LINE_LEFT | render.LINE_RIGHT | render.LINE_UP
	case '┼', '╋', '╬':
		return render.LINE_LEFT | render.LINE_RIGHT | render.LINE_UP | render.LINE_DOWN
	}

	return 0
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

draw_native_chrome :: proc(state: ^State, surface: ^render.Screen_Buffer, app: ^domain.App, mode: input.Input_Mode, output_pixel_width := 0, output_pixel_height := 0) {
	workspace := domain.active_workspace(app)
	if workspace == nil || workspace.root == nil {
		return
	}

	draw_native_pane_borders(state, surface, workspace.root, workspace.focused_pane_id, mode, output_pixel_width, output_pixel_height)
	draw_native_tab_borders(state, surface, workspace.root)
	draw_native_workspace_bar_borders(state, surface, app, output_pixel_height)
}

draw_native_tab_borders :: proc(state: ^State, surface: ^render.Screen_Buffer, node: ^domain.Node) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		return
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			draw_native_tab_borders(state, surface, child)
		}
	case .Stacked, .Tabbed:
		border := surface.bar.separator
		for child in node.children {
			deco := child.deco_bounds
			if deco.width <= 0 || deco.height <= 0 {
				continue
			}
			draw_native_rect_border(
				state,
				deco.x * state.cell_width,
				deco.y * state.cell_height,
				deco.width * state.cell_width,
				deco.height * state.cell_height,
				border,
				1,
			)
		}

		child := domain.focused_child(node)
		if child != nil {
			draw_native_tab_borders(state, surface, child)
		}
	}
}

draw_native_pane_borders :: proc(state: ^State, surface: ^render.Screen_Buffer, node: ^domain.Node, focused_pane_id: int, mode: input.Input_Mode, output_pixel_width := 0, output_pixel_height := 0) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil {
			return
		}

		color := render.Cell_Color.Inactive
		if node.pane.id == focused_pane_id {
			color = .Focused
			if mode == .Resize {
				color = .Split_Hint
			}
		} else if node.parent != nil && len(node.parent.focus_order) > 0 && node.parent.focus_order[0] == node {
			color = .Focused_Inactive
		}

		r, g, b := cell_color(surface, render.Cell{color = color})
		draw_native_pane_border(state, surface, node.pane.bounds, r, g, b, output_pixel_width, output_pixel_height)
		if node.pane.id == focused_pane_id && mode != .Resize && node.pane.split_active {
			hint_r, hint_g, hint_b := cell_color(surface, render.Cell{color = .Split_Hint})
			draw_native_split_hint(state, surface, node.pane.bounds, node.pane.split_kind, hint_r, hint_g, hint_b, output_pixel_width, output_pixel_height)
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			draw_native_pane_borders(state, surface, child, focused_pane_id, mode, output_pixel_width, output_pixel_height)
		}
	case .Stacked, .Tabbed:
		child := domain.focused_child(node)
		if child != nil {
			draw_native_pane_borders(state, surface, child, focused_pane_id, mode, output_pixel_width, output_pixel_height)
		}
	}
}

draw_native_split_hint :: proc(state: ^State, surface: ^render.Screen_Buffer, bounds: domain.Rect, split_kind: domain.Node_Kind, r: int, g: int, b: int, output_pixel_width := 0, output_pixel_height := 0) {
	pane_x, pane_y, pane_w, pane_h := native_pane_pixel_rect(state, surface, bounds, output_pixel_width, output_pixel_height)
	line_width := f32(max_int(state.native_border_px, 1))
	if pane_w <= 0 || pane_h <= 0 {
		return
	}

	sdl3.SetRenderDrawColor(state.renderer, u8(r), u8(g), u8(b), 255)
	if split_kind == .Split_Vertical {
		rect := sdl3.FRect{x = f32(pane_x), y = f32(pane_y + pane_h) - line_width, w = f32(pane_w), h = line_width}
		sdl3.RenderFillRect(state.renderer, &rect)
		return
	}

	rect := sdl3.FRect{x = f32(pane_x + pane_w) - line_width, y = f32(pane_y), w = line_width, h = f32(pane_h)}
	sdl3.RenderFillRect(state.renderer, &rect)
}

draw_native_pane_border :: proc(state: ^State, surface: ^render.Screen_Buffer, bounds: domain.Rect, r: int, g: int, b: int, output_pixel_width := 0, output_pixel_height := 0) {
	if bounds.width <= 0 || bounds.height <= 0 {
		return
	}

	pane_x, pane_y, pane_w, pane_h := native_pane_pixel_rect(state, surface, bounds, output_pixel_width, output_pixel_height)
	left := f32(pane_x)
	top := f32(pane_y)
	right := f32(pane_x + pane_w) - 1
	bottom := f32(pane_y + pane_h) - 1
	line_width := f32(max_int(state.native_border_px, 0))
	if line_width <= 0 {
		return
	}

	sdl3.SetRenderDrawColor(state.renderer, u8(r), u8(g), u8(b), 255)
	top_rect := sdl3.FRect{x = left, y = top, w = right - left + 1, h = line_width}
	bottom_rect := sdl3.FRect{x = left, y = bottom, w = right - left + 1, h = line_width}
	left_rect := sdl3.FRect{x = left, y = top, w = line_width, h = bottom - top + 1}
	right_rect := sdl3.FRect{x = right, y = top, w = line_width, h = bottom - top + 1}
	sdl3.RenderFillRect(state.renderer, &top_rect)
	sdl3.RenderFillRect(state.renderer, &bottom_rect)
	sdl3.RenderFillRect(state.renderer, &left_rect)
	sdl3.RenderFillRect(state.renderer, &right_rect)
}

native_cell_pane_bounds :: proc(app: ^domain.App, x: int, y: int) -> (domain.Rect, bool) {
	workspace := domain.active_workspace(app)
	if workspace == nil || workspace.root == nil {
		return domain.Rect{}, false
	}
	return native_cell_pane_bounds_node(workspace.root, x, y)
}

native_cell_pane_bounds_node :: proc(node: ^domain.Node, x: int, y: int) -> (domain.Rect, bool) {
	if node == nil {
		return domain.Rect{}, false
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil {
			return domain.Rect{}, false
		}
		bounds := node.pane.bounds
		if x >= bounds.x && x < bounds.x + bounds.width && y >= bounds.y && y < bounds.y + bounds.height {
			return bounds, true
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			bounds, ok := native_cell_pane_bounds_node(child, x, y)
			if ok {
				return bounds, true
			}
		}
	case .Stacked, .Tabbed:
		child := domain.focused_child(node)
		if child != nil {
			return native_cell_pane_bounds_node(child, x, y)
		}
	}

	return domain.Rect{}, false
}

draw_native_workspace_bar_borders :: proc(state: ^State, surface: ^render.Screen_Buffer, app: ^domain.App, output_pixel_height := 0) {
	if surface.height <= 0 {
		return
	}

	output_width := surface.width * state.cell_width
	if state.renderer != nil {
		pixel_width: c.int
		pixel_height: c.int
		if sdl3.GetRenderOutputSize(state.renderer, &pixel_width, &pixel_height) {
			output_width = int(pixel_width)
		}
	}

	workspace := domain.active_workspace(app)
	if workspace == nil {
		return
	}

	bar_top := (surface.height - 1) * state.cell_height
	if output_pixel_height > 0 {
		bar_top = max_int(output_pixel_height - state.cell_height, 0)
	}

	separator := surface.bar.separator
	sdl3.SetRenderDrawColor(state.renderer, separator.r, separator.g, separator.b, 255)
	bar_line := sdl3.FRect{x = 0, y = f32(bar_top), w = f32(output_width), h = 1}
	sdl3.RenderFillRect(state.renderer, &bar_line)

	cursor_x := 0
	for index in 0 ..< len(app.workspaces) {
		workspace_button := &app.workspaces[index]
		colors := surface.bar.inactive_workspace
		if index == app.active_workspace_index {
			colors = surface.bar.focused_workspace
		}

		button_width := (len(workspace_button.name) + 2) * state.cell_width
		if button_width <= 0 {
			continue
		}

		draw_native_rect_border(
			state,
			cursor_x * state.cell_width,
			bar_top,
			button_width,
			state.cell_height,
			colors.border,
			1,
		)
		cursor_x += len(workspace_button.name) + 2
	}
}

draw_native_rect_border :: proc(state: ^State, x: int, y: int, width: int, height: int, color: render.RGB_Color, thickness: int) {
	if width <= 0 || height <= 0 || thickness <= 0 {
		return
	}

	sdl3.SetRenderDrawColor(state.renderer, color.r, color.g, color.b, 255)
	t := f32(thickness)
	left := f32(x)
	top := f32(y)
	right := f32(x + width - thickness)
	bottom := f32(y + height - thickness)
	w := f32(width)
	h := f32(height)

	top_rect := sdl3.FRect{x = left, y = top, w = w, h = t}
	bottom_rect := sdl3.FRect{x = left, y = bottom, w = w, h = t}
	left_rect := sdl3.FRect{x = left, y = top, w = t, h = h}
	right_rect := sdl3.FRect{x = right, y = top, w = t, h = h}
	sdl3.RenderFillRect(state.renderer, &top_rect)
	sdl3.RenderFillRect(state.renderer, &bottom_rect)
	sdl3.RenderFillRect(state.renderer, &left_rect)
	sdl3.RenderFillRect(state.renderer, &right_rect)
}

native_pane_pixel_rect :: proc(state: ^State, surface: ^render.Screen_Buffer, bounds: domain.Rect, output_pixel_width := 0, output_pixel_height := 0) -> (int, int, int, int) {
	x := bounds.x * state.cell_width
	y := bounds.y * state.cell_height
	w := bounds.width * state.cell_width
	h := bounds.height * state.cell_height

	// i3bar reserves fixed bar space at the screen edge; the workspace area gets
	// all remaining pixels. Our logical layout is still cell based, so give the
	// bottom-most pane any residual pixels above the fixed workspace bar instead
	// of leaving them below the bar or clipping the pane at the floored grid size.
	if output_pixel_width > 0 && bounds.x + bounds.width == surface.width {
		w = max_int(output_pixel_width - x, 0)
	}
	if output_pixel_height > 0 && bounds.y + bounds.height == surface.height - 1 {
		workspace_bottom := max_int(output_pixel_height - state.cell_height, 0)
		h = max_int(workspace_bottom - y, 0)
	}

	return x, y, w, h
}
