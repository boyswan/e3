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

# Run e3 using the Nix/direnv environment on Linux. Optionally pass a config path.
run config="": ghostty-build
    if [ -n "{{config}}" ]; then odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --gui --foreground --config "{{config}}"; else odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --gui --foreground; fi

# Run e3 with the TTY renderer. Optionally pass a config path.
tty config="": ghostty-build
    if [ -n "{{config}}" ]; then odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty --config "{{config}}"; else odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty; fi

# Build e3 using the Nix/direnv environment on Linux
build: ghostty-build
    odin build src -out:e3 -extra-linker-flags:"{{ghostty_ld_flags}}"

# Check Homebrew dependencies for macOS
macos-check:
    source scripts/macos-env.sh

# Run e3 on macOS without Nix. Optionally pass a config path.
macos-run config="": ghostty-build
    source scripts/macos-env.sh && if [ -n "{{config}}" ]; then odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --gui --foreground --config "{{config}}"; else odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --gui --foreground; fi

# Run e3 with the TTY renderer on macOS without Nix. Optionally pass a config path.
macos-tty config="": ghostty-build
    source scripts/macos-env.sh && if [ -n "{{config}}" ]; then odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty --config "{{config}}"; else odin run src -extra-linker-flags:"{{ghostty_ld_flags}}" -- --tty; fi

# Build e3 on macOS without Nix
macos-build: ghostty-build
    source scripts/macos-env.sh && odin build src -out:e3 -extra-linker-flags:"{{ghostty_ld_flags}}"

# Build a relocatable release archive. libghostty-vt is linked statically;
# SDL3 and SDL3_ttf remain Homebrew runtime dependencies.
release version="0.1.0-dev": ghostty-build
    set -eu; \
    version="{{version}}"; \
    platform="{{ghostty_platform}}"; \
    static_dir="$(pwd)/build/ghostty-static/$platform"; \
    package_dir="$(pwd)/build/package/e3-$version-$platform"; \
    archive="$(pwd)/dist/e3-$version-$platform.tar.gz"; \
    rm -rf "$static_dir" "$package_dir"; \
    mkdir -p "$static_dir" "$package_dir" "$(pwd)/dist"; \
    cp "{{ghostty_prefix}}/lib/libghostty-vt.a" "$static_dir/"; \
    if [ "$(uname -s)" = Darwin ]; then source scripts/macos-env.sh; fi; \
    odin build src -out:"$package_dir/e3" -o:speed -source-code-locations:none -define:E3_VERSION="$version" -extra-linker-flags:"-L$static_dir"; \
    if [ "$(uname -s)" = Darwin ]; then strip -x "$package_dir/e3"; else strip --strip-unneeded "$package_dir/e3"; fi; \
    cp config.example.yaml README.md "$package_dir/"; \
    if [ -f LICENSE ]; then cp LICENSE "$package_dir/"; fi; \
    if [ "$(uname -s)" = Darwin ] && otool -L "$package_dir/e3" | grep -q libghostty-vt; then echo "release binary still links dynamic libghostty-vt" >&2; exit 1; fi; \
    if LC_ALL=C strings "$package_dir/e3" | grep -E -q "$(pwd)|/Users/|/home/|/opt/homebrew/Cellar|/usr/local/Cellar"; then echo "release binary contains a local build path" >&2; exit 1; fi; \
    tar -czf "$archive" -C "$(dirname "$package_dir")" "$(basename "$package_dir")"; \
    shasum -a 256 "$archive"; \
    echo "$archive"

# Build a self-contained macOS application archive for the Homebrew cask.
# Requires dylibbundler (`brew install dylibbundler`).
release-app version="0.1.0-dev":
    set -eu; \
    if [ "$(uname -s)" != Darwin ]; then echo "release-app requires macOS" >&2; exit 1; fi; \
    version="{{version}}"; \
    platform="{{ghostty_platform}}"; \
    just release "$version"; \
    package_binary="$(pwd)/build/package/e3-$version-$platform/e3"; \
    app_root="$(pwd)/build/app/$platform"; \
    app_dir="$app_root/e3.app"; \
    archive="$(pwd)/dist/e3-$version-$platform-app.zip"; \
    rm -rf "$app_root" "$archive"; \
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources"; \
    cp "$package_binary" "$app_dir/Contents/MacOS/e3"; \
    sed "s/@VERSION@/$version/g" packaging/macos/Info.plist.in > "$app_dir/Contents/Info.plist"; \
    cp config.example.yaml "$app_dir/Contents/Resources/"; \
    cp LICENSE "$app_dir/Contents/Resources/"; \
    iconset="$app_root/e3.iconset"; mkdir -p "$iconset"; \
    icon_png="$app_root/e3-icon.png"; sips -s format png packaging/macos/icon.svg --out "$icon_png" >/dev/null; \
    for entry in 16:icon_16x16.png 32:icon_16x16@2x.png 32:icon_32x32.png 64:icon_32x32@2x.png 128:icon_128x128.png 256:icon_128x128@2x.png 256:icon_256x256.png 512:icon_256x256@2x.png 512:icon_512x512.png 1024:icon_512x512@2x.png; do size="${entry%%:*}"; name="${entry#*:}"; sips -z "$size" "$size" "$icon_png" --out "$iconset/$name" >/dev/null; done; \
    iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/e3.icns"; \
    plutil -lint "$app_dir/Contents/Info.plist"; \
    (cd "$app_dir" && dylibbundler -od -b -x Contents/MacOS/e3 -d Contents/Frameworks -p @executable_path/../Frameworks); \
    if find "$app_dir/Contents" -type f -print0 | xargs -0 file | grep 'Mach-O' | cut -d: -f1 | while IFS= read -r binary; do otool -L "$binary"; done | grep -E -q '/opt/homebrew|/usr/local'; then echo "app bundle contains an unbundled Homebrew library path" >&2; exit 1; fi; \
    codesign --force --deep --sign - --timestamp=none "$app_dir"; \
    codesign --verify --deep --strict "$app_dir"; \
    ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"; \
    shasum -a 256 "$archive"; \
    echo "$archive"

# Print the macOS environment setup command for interactive shells
macos-env:
    @echo 'source scripts/macos-env.sh'
