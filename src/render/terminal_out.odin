package render

import "core:fmt"

tty_clear_screen :: proc() {
	fmt.print("\x1b[2J")
}

tty_move_cursor :: proc(x: int, y: int) {
	fmt.printf("\x1b[%d;%dH", y + 1, x + 1)
}

tty_hide_cursor :: proc() {
	fmt.print("\x1b[?25l")
}

tty_show_cursor :: proc() {
	fmt.print("\x1b[?25h")
}

tty_enter_alternate_screen :: proc() {
	fmt.print("\x1b[?1049h")
}

tty_leave_alternate_screen :: proc() {
	fmt.print("\x1b[?1049l")
}

tty_enter_app_screen :: proc() {
	tty_enter_alternate_screen()
	tty_hide_cursor()
	tty_clear_screen()
}

tty_leave_app_screen :: proc() {
	fmt.print("\x1b[0m")
	tty_show_cursor()
	tty_leave_alternate_screen()
}

tty_present :: proc(buffer: ^Screen_Buffer) {
	tty_hide_cursor()

	bold := false
	color := Cell_Color.Default
	for y in 0 ..< buffer.height {
		tty_move_cursor(0, y)

		for x in 0 ..< buffer.width {
			index := y * buffer.width + x
			cell := buffer.cells[index]

			if cell.bold != bold || cell.color != color {
				tty_set_style(cell.bold, cell.color)
				bold = cell.bold
				color = cell.color
			}

			fmt.print(cell.glyph)
		}
	}

	fmt.print("\x1b[0m")
}

tty_set_style :: proc(bold: bool, color: Cell_Color) {
	fmt.print("\x1b[0m")

	if bold {
		fmt.print("\x1b[1m")
	}

	switch color {
	case .Default:
		// Default foreground.
	case .Focused:
		fmt.print("\x1b[36m")
	case .Split_Hint:
		fmt.print("\x1b[35m")
	}
}
