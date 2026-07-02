package render

import app "../app"
import vt "../terminal"

render_terminal_contents :: proc(buffer: ^Screen_Buffer, pane: ^app.Pane, focused := false, inset := 1) {
	term := &pane.terminal
	if term.backend == .Ghostty {
		render_ghostty_contents(buffer, pane, focused, inset)
		return
	}

	if !term.active || term.cells == nil {
		return
	}

	bounds := pane.bounds
	start_x := bounds.x + inset
	start_y := bounds.y + inset
	max_width := terminal_min_int(term.width, terminal_max_int(bounds.width - inset * 2, 0))
	max_height := terminal_min_int(term.height, terminal_max_int(bounds.height - inset * 2, 0))

	for y in 0 ..< max_height {
		for x in 0 ..< max_width {
			value := term.cells[y * term.width + x]
			screen_put(buffer, start_x + x, start_y + y, terminal_glyph(value))
		}
	}
}

render_ghostty_contents :: proc(buffer: ^Screen_Buffer, pane: ^app.Pane, focused: bool, inset := 1) {
	term := &pane.terminal
	if !term.active || term.ghostty == nil || term.render_state == nil {
		return
	}

	bounds := pane.bounds
	start_x := bounds.x + inset
	start_y := bounds.y + inset
	max_width := terminal_min_int(term.width, terminal_max_int(bounds.width - inset * 2, 0))
	max_height := terminal_min_int(term.height, terminal_max_int(bounds.height - inset * 2, 0))
	if max_width <= 0 || max_height <= 0 {
		return
	}

	terminal_ghostty_apply_default_colors(buffer, term.ghostty)

	if vt.ghostty_render_state_update(term.render_state, term.ghostty) != .SUCCESS {
		return
	}
	if vt.ghostty_render_state_get(term.render_state, .ROW_ITERATOR, &term.row_iterator) != .SUCCESS {
		return
	}

	cursor_x: u16 = 0
	cursor_y: u16 = 0
	cursor_visible := false
	if focused {
		has_value := false
		if vt.ghostty_render_state_get(term.render_state, .CURSOR_VIEWPORT_HAS_VALUE, &has_value) == .SUCCESS && has_value {
			if vt.ghostty_render_state_get(term.render_state, .CURSOR_VIEWPORT_X, &cursor_x) == .SUCCESS &&
			   vt.ghostty_render_state_get(term.render_state, .CURSOR_VIEWPORT_Y, &cursor_y) == .SUCCESS {
				cursor_visible = true
			}
		}
	}

	row := 0
	for row < max_height && vt.ghostty_render_state_row_iterator_next(term.row_iterator) {
		if vt.ghostty_render_state_row_get(term.row_iterator, .CELLS, &term.row_cells) != .SUCCESS {
			row += 1
			continue
		}

		col := 0
		for col < max_width && vt.ghostty_render_state_row_cells_next(term.row_cells) {
			cursor_here := cursor_visible && u16(col) == cursor_x && u16(row) == cursor_y
			render_ghostty_cell(buffer, term.row_cells, start_x + col, start_y + row, cursor_here)
			col += 1
		}
		row += 1
	}
}

render_ghostty_cell :: proc(buffer: ^Screen_Buffer, row_cells: vt.GhosttyRenderStateRowCells, x: int, y: int, cursor_here := false) {
	glyph := terminal_ghostty_cell_rune(row_cells)

	style := vt.GhosttyStyle{size = size_of(vt.GhosttyStyle)}
	has_style := vt.ghostty_render_state_row_cells_get(row_cells, .STYLE, &style) == .SUCCESS
	bold := has_style && style.bold
	inverse := has_style && style.inverse

	fg_set, fg_r, fg_g, fg_b := terminal_ghostty_cell_color(row_cells, .FG_COLOR)
	bg_set, bg_r, bg_g, bg_b := terminal_ghostty_cell_color(row_cells, .BG_COLOR)

	if inverse || cursor_here {
		swap_fg_set := bg_set
		swap_fg_r, swap_fg_g, swap_fg_b := bg_r, bg_g, bg_b
		if !swap_fg_set {
			swap_fg_r, swap_fg_g, swap_fg_b = buffer.background_r, buffer.background_g, buffer.background_b
		}

		bg_set = fg_set
		bg_r, bg_g, bg_b = fg_r, fg_g, fg_b
		if !bg_set {
			bg_r, bg_g, bg_b = buffer.foreground_r, buffer.foreground_g, buffer.foreground_b
		}

		fg_set = true
		fg_r, fg_g, fg_b = swap_fg_r, swap_fg_g, swap_fg_b
		bg_set = true
	}

	screen_put_terminal_rune(
		buffer,
		x,
		y,
		glyph,
		bold,
		fg_set,
		fg_r,
		fg_g,
		fg_b,
		bg_set,
		bg_r,
		bg_g,
		bg_b,
	)
}

terminal_ghostty_cell_rune :: proc(row_cells: vt.GhosttyRenderStateRowCells) -> u32 {
	graphemes_len: u32 = 0
	if vt.ghostty_render_state_row_cells_get(row_cells, .GRAPHEMES_LEN, &graphemes_len) != .SUCCESS || graphemes_len == 0 {
		return ' '
	}

	codepoints: [8]u32
	if vt.ghostty_render_state_row_cells_get(row_cells, .GRAPHEMES_BUF, &codepoints) != .SUCCESS {
		return '?'
	}
	if codepoints[0] == 0 {
		return ' '
	}
	return codepoints[0]
}

terminal_ghostty_cell_color :: proc(row_cells: vt.GhosttyRenderStateRowCells, data: vt.GhosttyRenderStateRowCellsData) -> (bool, u8, u8, u8) {
	color: vt.GhosttyColorRgb
	if vt.ghostty_render_state_row_cells_get(row_cells, data, &color) != .SUCCESS {
		return false, 0, 0, 0
	}
	return true, color.r, color.g, color.b
}

terminal_ghostty_apply_default_colors :: proc(buffer: ^Screen_Buffer, ghostty: vt.GhosttyTerminal) {
	default_fg := vt.GhosttyColorRgb {
		r = buffer.foreground_r,
		g = buffer.foreground_g,
		b = buffer.foreground_b,
	}
	default_bg := vt.GhosttyColorRgb {
		r = buffer.background_r,
		g = buffer.background_g,
		b = buffer.background_b,
	}
	vt.ghostty_terminal_set(ghostty, .COLOR_FOREGROUND, &default_fg)
	vt.ghostty_terminal_set(ghostty, .COLOR_BACKGROUND, &default_bg)

	// Keep ghostty's default palette for colors 16..255 and override the
	// first 16 entries from the configured palette.
	palette: [256]vt.GhosttyColorRgb
	if vt.ghostty_terminal_get(ghostty, .COLOR_PALETTE_DEFAULT, &palette) != .SUCCESS {
		return
	}
	for index in 0 ..< len(buffer.palette) {
		palette[index] = vt.GhosttyColorRgb {
			r = buffer.palette[index].r,
			g = buffer.palette[index].g,
			b = buffer.palette[index].b,
		}
	}
	vt.ghostty_terminal_set(ghostty, .COLOR_PALETTE, &palette)
}

terminal_min_int :: proc(a: int, b: int) -> int {
	if a < b {
		return a
	}
	return b
}

terminal_max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

terminal_glyph :: proc(value: byte) -> string {
	switch value {
	case 32: return " "
	case 33: return "!"
	case 34: return "\""
	case 35: return "#"
	case 36: return "$"
	case 37: return "%"
	case 38: return "&"
	case 39: return "'"
	case 40: return "("
	case 41: return ")"
	case 42: return "*"
	case 43: return "+"
	case 44: return ","
	case 45: return "-"
	case 46: return "."
	case 47: return "/"
	case 48: return "0"
	case 49: return "1"
	case 50: return "2"
	case 51: return "3"
	case 52: return "4"
	case 53: return "5"
	case 54: return "6"
	case 55: return "7"
	case 56: return "8"
	case 57: return "9"
	case 58: return ":"
	case 59: return ";"
	case 60: return "<"
	case 61: return "="
	case 62: return ">"
	case 63: return "?"
	case 64: return "@"
	case 65: return "A"
	case 66: return "B"
	case 67: return "C"
	case 68: return "D"
	case 69: return "E"
	case 70: return "F"
	case 71: return "G"
	case 72: return "H"
	case 73: return "I"
	case 74: return "J"
	case 75: return "K"
	case 76: return "L"
	case 77: return "M"
	case 78: return "N"
	case 79: return "O"
	case 80: return "P"
	case 81: return "Q"
	case 82: return "R"
	case 83: return "S"
	case 84: return "T"
	case 85: return "U"
	case 86: return "V"
	case 87: return "W"
	case 88: return "X"
	case 89: return "Y"
	case 90: return "Z"
	case 91: return "["
	case 92: return "\\"
	case 93: return "]"
	case 94: return "^"
	case 95: return "_"
	case 96: return "`"
	case 97: return "a"
	case 98: return "b"
	case 99: return "c"
	case 100: return "d"
	case 101: return "e"
	case 102: return "f"
	case 103: return "g"
	case 104: return "h"
	case 105: return "i"
	case 106: return "j"
	case 107: return "k"
	case 108: return "l"
	case 109: return "m"
	case 110: return "n"
	case 111: return "o"
	case 112: return "p"
	case 113: return "q"
	case 114: return "r"
	case 115: return "s"
	case 116: return "t"
	case 117: return "u"
	case 118: return "v"
	case 119: return "w"
	case 120: return "x"
	case 121: return "y"
	case 122: return "z"
	case 123: return "{"
	case 124: return "|"
	case 125: return "}"
	case 126: return "~"
	}
	return "?"
}
