package main

import "core:fmt"
import "core:os"
import posix "core:sys/posix"

E3_VERSION :: #config(E3_VERSION, "0.1.3-dev")

handle_metadata_args :: proc() -> bool {
	for arg in os.args {
		switch arg {
		case "--version", "-V":
			fmt.printf("e3 %s\n", E3_VERSION)
			return true
		case "--help", "-h":
			print_usage()
			return true
		}
	}
	return false
}

detach_requested :: proc() -> bool {
	for arg in os.args {
		if arg == "--detach" {
			return true
		}
	}
	return false
}

foreground_requested :: proc() -> bool {
	for arg in os.args {
		if arg == "--foreground" {
			return true
		}
	}
	return false
}

// detach_process uses the conventional double-fork pattern. It is called
// before SDL/AppKit initialization so the detached child starts UI frameworks
// in a clean process state.
detach_process :: proc() -> (parent_should_exit: bool, ok: bool) {
	first_pid := posix.fork()
	if first_pid < 0 {
		fmt.eprintln("e3: failed to fork detached process")
		return false, false
	}
	if first_pid > 0 {
		return true, true
	}

	if posix.setsid() < 0 {
		fmt.eprintln("e3: failed to create detached session")
		posix._exit(1)
	}

	second_pid := posix.fork()
	if second_pid < 0 {
		fmt.eprintln("e3: failed to fork detached session")
		posix._exit(1)
	}
	if second_pid > 0 {
		posix._exit(0)
	}

	null_fd := posix.open("/dev/null", {.RDWR})
	if null_fd >= 0 {
		_ = posix.dup2(null_fd, posix.FD(0))
		_ = posix.dup2(null_fd, posix.FD(1))
		_ = posix.dup2(null_fd, posix.FD(2))
		if null_fd > 2 {
			_ = posix.close(null_fd)
		}
	}
	return false, true
}

print_usage :: proc() {
	fmt.println("e3 - an i3-inspired terminal multiplexer")
	fmt.println()
	fmt.println("Usage: e3 [OPTIONS]")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -c, --config PATH  Load an explicit configuration file")
	fmt.println("      --tty          Force the terminal renderer")
	fmt.println("      --gui          Force the SDL window renderer")
	fmt.println("      --detach       Launch an independent SDL window")
	fmt.println("      --foreground   Keep an SDL process attached for logging/debugging")
	fmt.println("  -V, --version      Print version and exit")
	fmt.println("  -h, --help         Print help and exit")
}
