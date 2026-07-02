set shell := ["bash", "-cu"]

ghostty_platform := `echo "$(uname -s)-$(uname -m)"`
ghostty_prefix := justfile_directory() / "vendor/ghostty-vt" / ghostty_platform
ghostty_ld_flags := "-L" + ghostty_prefix / "lib" + " -Wl,-rpath," + ghostty_prefix / "lib"

# List available recipes
_default:
    @just --list

# Fetch a Ghostty-compatible Zig locally unless GHOSTTY_ZIG is already set.
ghostty-zig:
    set -eu; \
    if [ -n "${GHOSTTY_ZIG:-}" ]; then exit 0; fi; \
    version="0.15.2"; \
    case "$(uname -s)-$(uname -m)" in \
        Darwin-arm64) target="aarch64-macos" ;; \
        Darwin-x86_64) target="x86_64-macos" ;; \
        Linux-aarch64) target="aarch64-linux" ;; \
        Linux-x86_64) target="x86_64-linux" ;; \
        *) echo "unsupported Zig host: $(uname -s)-$(uname -m)" >&2; exit 1 ;; \
    esac; \
    out=".deps/zig-$version"; \
    if [ -x "$out/zig" ]; then exit 0; fi; \
    mkdir -p .deps; \
    tmp=".deps/zig-$version.tar.xz"; \
    curl -L "https://ziglang.org/download/$version/zig-$target-$version.tar.xz" -o "$tmp"; \
    rm -rf "$out" ".deps/zig-$target-$version"; \
    tar -xf "$tmp" -C .deps; \
    mv ".deps/zig-$target-$version" "$out"

# Fetch the upstream Ghostty source used to build libghostty-vt.
ghostty-fetch:
    set -eu; \
    mkdir -p .deps; \
    if [ ! -d .deps/ghostty/.git ]; then \
        git clone https://github.com/ghostty-org/ghostty.git .deps/ghostty; \
    fi; \
    cd .deps/ghostty; \
    git fetch --depth 1 origin ae52f97dcac558735cfa916ea3965f247e5c6e9e; \
    git checkout ae52f97dcac558735cfa916ea3965f247e5c6e9e

# Build libghostty-vt into vendor/ghostty-vt/<os>-<arch>.
# Set GHOSTTY_ZIG=/path/to/zig if Ghostty needs a different Zig than this project.
ghostty-build: ghostty-zig ghostty-fetch
    set -eu; \
    prefix="{{ghostty_prefix}}"; \
    if [ -f "$prefix/lib/libghostty-vt.so" ] || [ -f "$prefix/lib/libghostty-vt.dylib" ]; then exit 0; fi; \
    ghostty_zig="${GHOSTTY_ZIG:-$(pwd)/.deps/zig-0.15.2/zig}"; \
    cd .deps/ghostty; \
    "$ghostty_zig" build -Demit-lib-vt=true -Demit-xcframework=false -Doptimize=ReleaseFast --prefix "$prefix"

# Run e3 using the Nix/direnv environment on Linux
run: ghostty-build
    odin run src -extra-linker-flags:"{{ghostty_ld_flags}}"

# Run e3 with the TTY renderer
tty: ghostty-build
    odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty

# Build e3 using the Nix/direnv environment on Linux
build: ghostty-build
    odin build src -out:e3 -extra-linker-flags:"{{ghostty_ld_flags}}"

# Check Homebrew dependencies for macOS
macos-check:
    source scripts/macos-env.sh

# Run e3 on macOS without Nix
macos-run: ghostty-build
    source scripts/macos-env.sh && odin run src -extra-linker-flags:"{{ghostty_ld_flags}}"

# Run e3 with the TTY renderer on macOS without Nix
macos-tty: ghostty-build
    source scripts/macos-env.sh && odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty

# Build e3 on macOS without Nix
macos-build: ghostty-build
    source scripts/macos-env.sh && odin build src -out:e3 -extra-linker-flags:"{{ghostty_ld_flags}}"

# Print the macOS environment setup command for interactive shells
macos-env:
    @echo 'source scripts/macos-env.sh'
