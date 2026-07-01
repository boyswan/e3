package platform

import posix "core:sys/posix"

Terminal_Mode :: struct {
	original: posix.termios,
	active:   bool,
}

terminal_enter_raw_mode :: proc(mode: ^Terminal_Mode) -> bool {
	if posix.tcgetattr(posix.FD(0), &mode.original) != .OK {
		return false
	}

	raw := mode.original
	raw.c_lflag -= {.ECHO, .ICANON}
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

terminal_restore_mode :: proc(mode: ^Terminal_Mode) {
	if !mode.active {
		return
	}

	posix.tcsetattr(posix.FD(0), .TCSAFLUSH, &mode.original)
	mode.active = false
}
