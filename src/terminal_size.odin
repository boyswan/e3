package app

import "core:c"

foreign import libc "system:c"

foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, argp: rawptr) -> c.int ---
}

TIOCGWINSZ :: c.ulong(0x5413)

Terminal_Winsize :: struct {
	row:    u16,
	col:    u16,
	xpixel: u16,
	ypixel: u16,
}

terminal_size :: proc() -> (int, int, bool) {
	if width, height, ok := terminal_size_from_fd(1); ok {
		return width, height, true
	}

	if width, height, ok := terminal_size_from_fd(0); ok {
		return width, height, true
	}

	if width, height, ok := terminal_size_from_fd(2); ok {
		return width, height, true
	}

	return 0, 0, false
}

terminal_size_from_fd :: proc(fd: c.int) -> (int, int, bool) {
	winsize: Terminal_Winsize
	result := ioctl(fd, TIOCGWINSZ, &winsize)
	if result != 0 || winsize.col == 0 || winsize.row == 0 {
		return 0, 0, false
	}

	return int(winsize.col), int(winsize.row), true
}

terminal_size_or_default :: proc(default_width: int, default_height: int) -> (int, int) {
	if width, height, ok := terminal_size(); ok {
		return width, height
	}

	return default_width, default_height
}
