package tty

import "core:fmt"
import render "../render"

clear_screen :: proc() {
	fmt.print("\x1b[2J")
}

move_cursor :: proc(x: int, y: int) {
	fmt.printf("\x1b[%d;%dH", y + 1, x + 1)
}

hide_cursor :: proc() {
	fmt.print("\x1b[?25l")
}

show_cursor :: proc() {
	fmt.print("\x1b[?25h")
}

enter_alternate_screen :: proc() {
	fmt.print("\x1b[?1049h")
}

leave_alternate_screen :: proc() {
	fmt.print("\x1b[?1049l")
}

enter_app_screen :: proc() {
	enter_alternate_screen()
	hide_cursor()
	clear_screen()
}

leave_app_screen :: proc() {
	fmt.print("\x1b[0m")
	show_cursor()
	leave_alternate_screen()
}

present :: proc(buffer: ^render.Screen_Buffer) {
	hide_cursor()

	style := render.Cell{glyph = " "}
	for y in 0 ..< buffer.height {
		move_cursor(0, y)

		for x in 0 ..< buffer.width {
			index := y * buffer.width + x
			cell := buffer.cells[index]

			if !style_equal(style, cell) {
				set_style(buffer, cell)
				style = cell
			}

			print_cell(cell)
		}
	}

	fmt.print("\x1b[0m")
}

print_cell :: proc(cell: render.Cell) {
	if cell.rune != 0 {
		buf: [4]u8
		count := encode_utf8(cell.rune, buf[:])
		if count > 0 {
			fmt.print(string(buf[:count]))
		}
		return
	}

	fmt.print(cell.glyph)
}

style_equal :: proc(a: render.Cell, b: render.Cell) -> bool {
	return a.bold == b.bold &&
		a.color == b.color &&
		a.fg_set == b.fg_set &&
		a.fg_r == b.fg_r &&
		a.fg_g == b.fg_g &&
		a.fg_b == b.fg_b &&
		a.bg_set == b.bg_set &&
		a.bg_r == b.bg_r &&
		a.bg_g == b.bg_g &&
		a.bg_b == b.bg_b
}

set_style :: proc(buffer: ^render.Screen_Buffer, cell: render.Cell) {
	fmt.print("\x1b[0m")

	if cell.bold {
		fmt.print("\x1b[1m")
	}

	switch cell.color {
	case .Default:
		if cell.fg_set {
			fmt.printf("\x1b[38;2;%d;%d;%dm", cell.fg_r, cell.fg_g, cell.fg_b)
		}
	case .Inactive:
		color := buffer.client.unfocused.child_border
		fmt.printf("\x1b[38;2;%d;%d;%dm", color.r, color.g, color.b)
	case .Focused_Inactive:
		color := buffer.client.focused_inactive.child_border
		fmt.printf("\x1b[38;2;%d;%d;%dm", color.r, color.g, color.b)
	case .Focused:
		color := buffer.client.focused.child_border
		fmt.printf("\x1b[38;2;%d;%d;%dm", color.r, color.g, color.b)
	case .Split_Hint:
		color := buffer.client.focused.indicator
		fmt.printf("\x1b[38;2;%d;%d;%dm", color.r, color.g, color.b)
	}

	if cell.bg_set && cell.color == .Default {
		fmt.printf("\x1b[48;2;%d;%d;%dm", cell.bg_r, cell.bg_g, cell.bg_b)
	}
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
