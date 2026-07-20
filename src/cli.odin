package main

import "core:fmt"
import "core:os"

E3_VERSION :: #config(E3_VERSION, "0.1.0-dev")

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

print_usage :: proc() {
	fmt.println("e3 - an i3-inspired terminal multiplexer")
	fmt.println()
	fmt.println("Usage: e3 [OPTIONS]")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -c, --config PATH  Load an explicit configuration file")
	fmt.println("      --tty          Use the terminal renderer")
	fmt.println("  -V, --version      Print version and exit")
	fmt.println("  -h, --help         Print help and exit")
}
