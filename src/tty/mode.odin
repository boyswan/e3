package tty

import posix "core:sys/posix"

Mode :: struct {
	original: posix.termios,
	active:   bool,
}

enter_raw_mode :: proc(mode: ^Mode) -> bool {
	if posix.tcgetattr(posix.FD(0), &mode.original) != .OK {
		return false
	}

	raw := mode.original
	// Disable the outer terminal's signal-generating line discipline. Control
	// bytes such as Ctrl+C (0x03), Ctrl+\\ (0x1c), and Ctrl+Z (0x1a) must reach
	// the focused pane PTY, whose own line discipline signals its foreground
	// process. Otherwise the outer terminal sends SIGINT/SIGQUIT/SIGTSTP to e3.
	raw.c_lflag -= {.ECHO, .ICANON, .ISIG, .IEXTEN}
	raw.c_iflag -= {.ICRNL, .IXON}
	raw.c_oflag -= {.OPOST}
	raw.c_cc[.VMIN] = posix.cc_t(1)
	raw.c_cc[.VTIME] = posix.cc_t(0)

	if posix.tcsetattr(posix.FD(0), .TCSAFLUSH, &raw) != .OK {
		return false
	}

	mode.active = true
	return true
}

restore_mode :: proc(mode: ^Mode) {
	if !mode.active {
		return
	}

	posix.tcsetattr(posix.FD(0), .TCSAFLUSH, &mode.original)
	mode.active = false
}
