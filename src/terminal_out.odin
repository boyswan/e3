package app

import "core:fmt"

terminal_clear_screen :: proc() {
	fmt.print("\x1b[2J")
}

terminal_move_cursor :: proc(x: int, y: int) {
	fmt.printf("\x1b[%d;%dH", y + 1, x + 1)
}

terminal_hide_cursor :: proc() {
	fmt.print("\x1b[?25l")
}

terminal_show_cursor :: proc() {
	fmt.print("\x1b[?25h")
}

terminal_enter_alternate_screen :: proc() {
	fmt.print("\x1b[?1049h")
}

terminal_leave_alternate_screen :: proc() {
	fmt.print("\x1b[?1049l")
}

terminal_enter_app_screen :: proc() {
	terminal_enter_alternate_screen()
	terminal_hide_cursor()
	terminal_clear_screen()
}

terminal_leave_app_screen :: proc() {
	fmt.print("\x1b[0m")
	terminal_show_cursor()
	terminal_leave_alternate_screen()
}

terminal_flush_screen :: proc(buffer: ^Screen_Buffer) {
	terminal_hide_cursor()

	bold := false
	color := Cell_Color.Default
	for y in 0 ..< buffer.height {
		terminal_move_cursor(0, y)

		for x in 0 ..< buffer.width {
			index := y * buffer.width + x
			cell := buffer.cells[index]

			if cell.bold != bold || cell.color != color {
				terminal_set_style(cell.bold, cell.color)
				bold = cell.bold
				color = cell.color
			}

			fmt.print(cell.glyph)
		}
	}

	fmt.print("\x1b[0m")
}

terminal_set_style :: proc(bold: bool, color: Cell_Color) {
	fmt.print("\x1b[0m")

	if bold {
		fmt.print("\x1b[1m")
	}

	switch color {
	case .Default:
		// Default foreground.
	case .Focused:
		fmt.print("\x1b[36m")
	}
}
