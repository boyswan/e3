package render

import domain "../app"

LINE_UP    :: u8(1 << 0)
LINE_DOWN  :: u8(1 << 1)
LINE_LEFT  :: u8(1 << 2)
LINE_RIGHT :: u8(1 << 3)

Cell_Color :: enum {
	Default,
	Inactive,
	Focused_Inactive,
	Focused,
	Split_Hint,
}

Cell :: struct {
	glyph:     string,
	rune:      u32,
	bold:      bool,
	color:     Cell_Color,
	line_mask: u8,

	fg_set: bool,
	fg_r:   u8,
	fg_g:   u8,
	fg_b:   u8,
	bg_set: bool,
	bg_r:   u8,
	bg_g:   u8,
	bg_b:   u8,
}

Screen_Buffer :: struct {
	width:  int,
	height: int,
	cells:  []Cell,

	background_r: u8,
	background_g: u8,
	background_b: u8,
	foreground_r: u8,
	foreground_g: u8,
	foreground_b: u8,
	palette:      [16]RGB_Color,
	bar:          Bar_Colors,
}

make_screen_buffer :: proc(width: int, height: int) -> Screen_Buffer {
	buffer := Screen_Buffer {
		width = width,
		height = height,
		cells = make([]Cell, width * height),
		background_r = 10,
		background_g = 10,
		background_b = 12,
		foreground_r = 220,
		foreground_g = 220,
		foreground_b = 220,
	}
	defaults := renderer_default_config()
	buffer.palette = defaults.palette
	buffer.bar = defaults.bar

	screen_clear(&buffer)
	return buffer
}

destroy_screen_buffer :: proc(buffer: ^Screen_Buffer) {
	if buffer.cells != nil {
		delete(buffer.cells)
	}

	buffer.width = 0
	buffer.height = 0
}

screen_set_background :: proc(buffer: ^Screen_Buffer, r: u8, g: u8, b: u8) {
	buffer.background_r = r
	buffer.background_g = g
	buffer.background_b = b
}

screen_set_foreground :: proc(buffer: ^Screen_Buffer, r: u8, g: u8, b: u8) {
	buffer.foreground_r = r
	buffer.foreground_g = g
	buffer.foreground_b = b
}

screen_set_palette :: proc(buffer: ^Screen_Buffer, palette: [16]RGB_Color) {
	buffer.palette = palette
}

screen_set_bar_colors :: proc(buffer: ^Screen_Buffer, bar: Bar_Colors) {
	buffer.bar = bar
}

screen_clear :: proc(buffer: ^Screen_Buffer) {
	for index in 0 ..< len(buffer.cells) {
		buffer.cells[index] = Cell{glyph = " ", color = .Default}
	}
}

screen_index :: proc(buffer: ^Screen_Buffer, x: int, y: int) -> (int, bool) {
	if x < 0 || y < 0 || x >= buffer.width || y >= buffer.height {
		return 0, false
	}

	return y * buffer.width + x, true
}

screen_put :: proc(buffer: ^Screen_Buffer, x: int, y: int, glyph: string, bold := false, color := Cell_Color.Default) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index] = Cell{glyph = glyph, bold = bold, color = color}
}

screen_put_rgb :: proc(buffer: ^Screen_Buffer, x: int, y: int, glyph: string, fg: RGB_Color, bg: RGB_Color, bold := false) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index] = Cell {
		glyph = glyph,
		bold = bold,
		color = .Default,
		fg_set = true,
		fg_r = fg.r,
		fg_g = fg.g,
		fg_b = fg.b,
		bg_set = true,
		bg_r = bg.r,
		bg_g = bg.g,
		bg_b = bg.b,
	}
}

screen_put_rune_rgb :: proc(buffer: ^Screen_Buffer, x: int, y: int, rune: u32, fg: RGB_Color, bg: RGB_Color, bold := false) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index] = Cell {
		glyph = " ",
		rune = rune,
		bold = bold,
		color = .Default,
		fg_set = true,
		fg_r = fg.r,
		fg_g = fg.g,
		fg_b = fg.b,
		bg_set = true,
		bg_r = bg.r,
		bg_g = bg.g,
		bg_b = bg.b,
	}
}

screen_put_terminal :: proc(
	buffer: ^Screen_Buffer,
	x: int,
	y: int,
	glyph: string,
	bold := false,
	fg_set := false,
	fg_r: u8 = 0,
	fg_g: u8 = 0,
	fg_b: u8 = 0,
	bg_set := false,
	bg_r: u8 = 0,
	bg_g: u8 = 0,
	bg_b: u8 = 0,
) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index] = Cell {
		glyph = glyph,
		bold = bold,
		color = .Default,
		fg_set = fg_set,
		fg_r = fg_r,
		fg_g = fg_g,
		fg_b = fg_b,
		bg_set = bg_set,
		bg_r = bg_r,
		bg_g = bg_g,
		bg_b = bg_b,
	}
}

screen_put_terminal_rune :: proc(
	buffer: ^Screen_Buffer,
	x: int,
	y: int,
	rune: u32,
	bold := false,
	fg_set := false,
	fg_r: u8 = 0,
	fg_g: u8 = 0,
	fg_b: u8 = 0,
	bg_set := false,
	bg_r: u8 = 0,
	bg_g: u8 = 0,
	bg_b: u8 = 0,
) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index] = Cell {
		glyph = " ",
		rune = rune,
		bold = bold,
		color = .Default,
		fg_set = fg_set,
		fg_r = fg_r,
		fg_g = fg_g,
		fg_b = fg_b,
		bg_set = bg_set,
		bg_r = bg_r,
		bg_g = bg_g,
		bg_b = bg_b,
	}
}

screen_put_line :: proc(buffer: ^Screen_Buffer, x: int, y: int, mask: u8, color := Cell_Color.Default) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	cell := &buffer.cells[index]
	cell.line_mask |= mask
	cell.glyph = line_glyph(cell.line_mask)
	cell.rune = 0
	cell.bold = false
	cell.color = color
	cell.fg_set = false
	cell.bg_set = false
}

screen_set_color :: proc(buffer: ^Screen_Buffer, x: int, y: int, color: Cell_Color) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	buffer.cells[index].color = color
}

screen_set_cell_background :: proc(buffer: ^Screen_Buffer, x: int, y: int, r: u8, g: u8, b: u8) {
	index, ok := screen_index(buffer, x, y)
	if !ok {
		return
	}

	cell := &buffer.cells[index]
	cell.bg_set = true
	cell.bg_r = r
	cell.bg_g = g
	cell.bg_b = b
}

screen_set_range_background :: proc(buffer: ^Screen_Buffer, x: int, y: int, width: int, r: u8, g: u8, b: u8) {
	for offset in 0 ..< width {
		screen_set_cell_background(buffer, x + offset, y, r, g, b)
	}
}

line_glyph :: proc(mask: u8) -> string {
	switch mask {
	case LINE_UP | LINE_DOWN:
		return "│"
	case LINE_LEFT | LINE_RIGHT:
		return "─"
	case LINE_DOWN | LINE_RIGHT:
		return "┌"
	case LINE_DOWN | LINE_LEFT:
		return "┐"
	case LINE_UP | LINE_RIGHT:
		return "└"
	case LINE_UP | LINE_LEFT:
		return "┘"
	case LINE_UP | LINE_DOWN | LINE_RIGHT:
		return "├"
	case LINE_UP | LINE_DOWN | LINE_LEFT:
		return "┤"
	case LINE_LEFT | LINE_RIGHT | LINE_DOWN:
		return "┬"
	case LINE_LEFT | LINE_RIGHT | LINE_UP:
		return "┴"
	case LINE_UP | LINE_DOWN | LINE_LEFT | LINE_RIGHT:
		return "┼"
	case LINE_UP, LINE_DOWN:
		return "│"
	case LINE_LEFT, LINE_RIGHT:
		return "─"
	}

	return " "
}

screen_put_text :: proc(buffer: ^Screen_Buffer, x: int, y: int, text: string, bold := false, color := Cell_Color.Default) -> int {
	cursor_x := x

	for offset in 0 ..< len(text) {
		screen_put(buffer, cursor_x, y, text[offset:offset + 1], bold, color)
		cursor_x += 1
	}

	return cursor_x
}

screen_put_int :: proc(buffer: ^Screen_Buffer, x: int, y: int, value: int, bold := false) -> int {
	cursor_x := x
	remaining := value
	if remaining < 0 {
		cursor_x = screen_put_text(buffer, cursor_x, y, "-", bold)
		remaining = -remaining
	}

	if remaining == 0 {
		return screen_put_text(buffer, cursor_x, y, "0", bold)
	}

	digits: [20]int
	count := 0
	for remaining > 0 && count < len(digits) {
		digits[count] = remaining % 10
		remaining /= 10
		count += 1
	}

	for count > 0 {
		count -= 1
		cursor_x = screen_put_text(buffer, cursor_x, y, digit_string(digits[count]), bold)
	}

	return cursor_x
}

digit_string :: proc(digit: int) -> string {
	switch digit {
	case 0:
		return "0"
	case 1:
		return "1"
	case 2:
		return "2"
	case 3:
		return "3"
	case 4:
		return "4"
	case 5:
		return "5"
	case 6:
		return "6"
	case 7:
		return "7"
	case 8:
		return "8"
	case 9:
		return "9"
	}

	return "?"
}

screen_draw_horizontal_line :: proc(buffer: ^Screen_Buffer, x: int, y: int, width: int) {
	if width <= 0 {
		return
	}

	for offset in 0 ..< width {
		mask := LINE_LEFT | LINE_RIGHT
		if offset == 0 {
			mask = LINE_RIGHT
		}
		if offset == width - 1 {
			mask = LINE_LEFT
		}
		if width == 1 {
			mask = LINE_LEFT | LINE_RIGHT
		}

		screen_put_line(buffer, x + offset, y, mask)
	}
}

screen_draw_vertical_line :: proc(buffer: ^Screen_Buffer, x: int, y: int, height: int) {
	if height <= 0 {
		return
	}

	for offset in 0 ..< height {
		mask := LINE_UP | LINE_DOWN
		if offset == 0 {
			mask = LINE_DOWN
		}
		if offset == height - 1 {
			mask = LINE_UP
		}
		if height == 1 {
			mask = LINE_UP | LINE_DOWN
		}

		screen_put_line(buffer, x, y + offset, mask)
	}
}

screen_draw_box :: proc(buffer: ^Screen_Buffer, bounds: domain.Rect) {
	if bounds.width < 2 || bounds.height < 2 {
		return
	}

	left := bounds.x
	right := bounds.x + bounds.width - 1
	top := bounds.y
	bottom := bounds.y + bounds.height - 1

	screen_put_line(buffer, left, top, LINE_DOWN | LINE_RIGHT)
	screen_draw_horizontal_line(buffer, left + 1, top, bounds.width - 2)
	screen_put_line(buffer, right, top, LINE_DOWN | LINE_LEFT)

	for y in top + 1 ..< bottom {
		screen_put_line(buffer, left, y, LINE_UP | LINE_DOWN)
		screen_put_line(buffer, right, y, LINE_UP | LINE_DOWN)
	}

	screen_put_line(buffer, left, bottom, LINE_UP | LINE_RIGHT)
	screen_draw_horizontal_line(buffer, left + 1, bottom, bounds.width - 2)
	screen_put_line(buffer, right, bottom, LINE_UP | LINE_LEFT)
}
