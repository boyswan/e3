package render

import "core:c"
import app "../app"
import vt "../terminal"

render_terminal_contents :: proc(buffer: ^Screen_Buffer, pane: ^app.Pane, focused := false, inset := 1) {
	term := &pane.terminal
	if term.backend == .Libvterm {
		render_libvterm_contents(buffer, pane, focused, inset)
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

render_libvterm_contents :: proc(buffer: ^Screen_Buffer, pane: ^app.Pane, focused: bool, inset := 1) {
	term := &pane.terminal
	if !term.active || term.vterm_screen == nil {
		return
	}

	bounds := pane.bounds
	start_x := bounds.x + inset
	start_y := bounds.y + inset
	max_width := terminal_min_int(term.width, terminal_max_int(bounds.width - inset * 2, 0))
	max_height := terminal_min_int(term.height, terminal_max_int(bounds.height - inset * 2, 0))

	terminal_vterm_apply_default_colors(buffer, term.vterm_state, term.vterm_screen)

	cursor := vt.VTermPos{row = -1, col = -1}
	if focused && term.vterm_state != nil {
		vt.get_cursorpos(term.vterm_state, &cursor)
	}

	for y in 0 ..< max_height {
		for x in 0 ..< max_width {
			cell: vt.VTermScreenCell
			ok := vt.get_cell(term.vterm_screen, vt.VTermPos{row = c.int(y), col = c.int(x)}, &cell)
			if ok == 0 {
				continue
			}

			glyph := terminal_vterm_glyph(cell.chars[0])
			bold := vt.cell_is_bold(&cell)
			fg := cell.fg
			bg := cell.bg
			emit_defaults := false
			if vt.cell_is_reverse(&cell) || (cursor.row == c.int(y) && cursor.col == c.int(x)) {
				fg, bg = bg, fg
				emit_defaults = true
			}
			fg_set, fg_r, fg_g, fg_b := terminal_vterm_foreground_color(buffer, term.vterm_screen, &fg, emit_defaults)
			bg_set, bg_r, bg_g, bg_b := terminal_vterm_background_color(buffer, term.vterm_screen, &bg, emit_defaults)
			screen_put_terminal_rune(
				buffer,
				start_x + x,
				start_y + y,
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
	}
}

terminal_vterm_apply_default_colors :: proc(buffer: ^Screen_Buffer, state: ^vt.VTermState, screen: ^vt.VTermScreen) {
	default_fg := vt.VTermColor {
		type = u8(vt.VTermColor_Type.RGB),
		red = buffer.foreground_r,
		green = buffer.foreground_g,
		blue = buffer.foreground_b,
	}
	default_bg := vt.VTermColor {
		type = u8(vt.VTermColor_Type.RGB),
		red = buffer.background_r,
		green = buffer.background_g,
		blue = buffer.background_b,
	}

	if state != nil {
		vt.set_state_default_colors(state, &default_fg, &default_bg)
		vt.set_bold_highbright(state, 0)
		for index in 0 ..< len(buffer.palette) {
			palette_color := vt.VTermColor {
				type = u8(vt.VTermColor_Type.RGB),
				red = buffer.palette[index].r,
				green = buffer.palette[index].g,
				blue = buffer.palette[index].b,
			}
			vt.set_palette_color(state, c.int(index), &palette_color)
		}
	}
	if screen != nil {
		vt.set_default_colors(screen, &default_fg, &default_bg)
	}
}

terminal_vterm_foreground_color :: proc(buffer: ^Screen_Buffer, screen: ^vt.VTermScreen, color: ^vt.VTermColor, emit_default: bool) -> (bool, u8, u8, u8) {
	if vt.color_is_default_fg(color) {
		if emit_default {
			return true, buffer.foreground_r, buffer.foreground_g, buffer.foreground_b
		}
		return false, 0, 0, 0
	}
	if vt.color_is_default_bg(color) {
		if emit_default {
			return true, buffer.background_r, buffer.background_g, buffer.background_b
		}
		return false, 0, 0, 0
	}

	converted := color^
	vt.convert_color_to_rgb(screen, &converted)
	return true, converted.red, converted.green, converted.blue
}

terminal_vterm_background_color :: proc(buffer: ^Screen_Buffer, screen: ^vt.VTermScreen, color: ^vt.VTermColor, emit_default: bool) -> (bool, u8, u8, u8) {
	if vt.color_is_default_bg(color) {
		if emit_default {
			return true, buffer.background_r, buffer.background_g, buffer.background_b
		}
		return false, 0, 0, 0
	}
	if vt.color_is_default_fg(color) {
		if emit_default {
			return true, buffer.foreground_r, buffer.foreground_g, buffer.foreground_b
		}
		return false, 0, 0, 0
	}

	converted := color^
	vt.convert_color_to_rgb(screen, &converted)
	return true, converted.red, converted.green, converted.blue
}

terminal_vterm_glyph :: proc(value: u32) -> u32 {
	if value == 0 {
		return ' '
	}
	return value
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
