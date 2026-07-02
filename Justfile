set shell := ["bash", "-cu"]

# List available recipes
_default:
    @just --list

# Run e3 using the Nix/direnv environment on Linux
run:
    odin run src

# Run e3 with the TTY renderer
tty:
    odin run src -- --tty

# Build e3 using the Nix/direnv environment on Linux
build:
    odin build src -out:e3

# Check Homebrew dependencies for macOS
macos-check:
    source scripts/macos-env.sh

# Run e3 on macOS without Nix
macos-run:
    source scripts/macos-env.sh && odin run src

# Run e3 with the TTY renderer on macOS without Nix
macos-tty:
    source scripts/macos-env.sh && trap 'stty sane; printf "\033[0m\033[?25h\033[?1049l"' EXIT && odin run src_tty

# Build e3 on macOS without Nix
macos-build:
    source scripts/macos-env.sh && odin build src -out:e3

# Print the macOS environment setup command for interactive shells
macos-env:
    @echo 'source scripts/macos-env.sh'

# Show the debug log written by macOS/Linux runs
log:
    @tail -200 /tmp/e3.log || true
