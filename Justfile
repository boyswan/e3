set shell := ["bash", "-cu"]

# List available recipes
_default:
    @just --list

# Run e3 using the Nix/direnv environment on Linux
run:
    odin run src

# Build e3 using the Nix/direnv environment on Linux
build:
    odin build src -out:e3

# Check Homebrew dependencies for macOS
macos-check:
    source scripts/macos-env.sh

# Run e3 on macOS without Nix
macos-run:
    source scripts/macos-env.sh && odin run src

# Build e3 on macOS without Nix
macos-build:
    source scripts/macos-env.sh && odin build src -out:e3

# Print the macOS environment setup command for interactive shells
macos-env:
    @echo 'source scripts/macos-env.sh'
