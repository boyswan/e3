# e3

An experimental Odin terminal multiplexer inspired by i3.

`e3` opens terminal panes, arranges them in an i3-style layout tree, and supports numbered workspaces, split layouts, focus movement, pane movement, resize mode, and configurable keybindings. It runs as a native SDL3 window by default, with an optional terminal/TTY renderer.

## Homebrew

```sh
brew tap boyswan/e3
brew trust boyswan/e3
brew install e3
```

## Requirements

The easiest way to get the required tools and libraries is with Nix:

```sh
nix develop
```

The development shell provides Odin, SDL3, SDL3_ttf, and Fontconfig. Terminal emulation is backed by [libghostty-vt](https://ghostty.org), which is fetched and built locally into `vendor/ghostty-vt/<os>-<arch>` by `just ghostty-build` (any `just run`/`just build` recipe triggers it automatically). Building it requires Zig 0.15.2, which the recipes download into `.deps/` when `GHOSTTY_ZIG` is not set.

### macOS without Nix

Install the dependencies with Homebrew:

```sh
brew install odin sdl3 sdl3_ttf
```

libghostty-vt is built from source via `just ghostty-build` (see above), so no Homebrew terminal library is needed. Building it requires the Xcode Command Line Tools (`xcode-select --install`), which Homebrew already depends on.

Then source the macOS environment helper before building or running:

```sh
source scripts/macos-env.sh
odin run src
# or, for the TTY renderer:
odin run src -- --tty
```

With `just` installed, the equivalent recipes are:

```sh
just macos-run
just macos-tty
just macos-build
```

macOS uses CoreText for `font.family` lookup, so Fontconfig is not required. Command is the built-in modifier on macOS; Linux defaults to Alt. Both can be overridden with `input.mod` in the user configuration.

## Run

From the project root:

```sh
odin run src
```

To use the terminal renderer instead of the default SDL3 window:

```sh
odin run src -- --tty
```

## Build

```sh
odin build src -out:e3
./e3
```

For a relocatable release archive with libghostty-vt linked statically:

```sh
just release 0.1.0
```

The archive is written to `dist/`. SDL3 and SDL3_ttf remain runtime dependencies. Homebrew formula packaging files are documented under `packaging/homebrew/`.

## Configuration

A configuration file is optional; e3 has portable built-in defaults. Configuration is loaded from the first existing path:

1. `$E3_CONFIG` (explicit override)
2. `$XDG_CONFIG_HOME/e3/config.yaml`
3. `~/.config/e3/config.yaml`
4. `~/Library/Application Support/e3/config.yaml` (macOS)

Pass an explicit file with `--config`, `--config=...`, or `-c`; this takes precedence over every environment/user path:

```sh
./e3 --config /path/to/config.yaml
# Development recipe shorthand:
just macos-run /path/to/config.yaml
```

`config.example.yaml` documents all current options. To customize e3:

```sh
mkdir -p ~/.config/e3
cp config.example.yaml ~/.config/e3/config.yaml
```

New panes execute `$SHELL` by default, falling back to `/bin/sh`. Override it with an executable path or name:

```yaml
shell:
  command: "/bin/zsh"
```

## Default keybindings

`Mod` is Command on macOS and Alt elsewhere.

| Binding | Action |
| --- | --- |
| `Mod+q` | Quit e3 |
| `Mod+d` | Set horizontal split context |
| `Mod+Shift+d` | Set vertical split context |
| `Mod+Enter` | Open pane in the active split context |
| `Mod+w` | Close focused pane |
| `Mod+h/j/k/l` | Focus left/down/up/right |
| `Mod+Shift+h/j/k/l` | Move pane left/down/up/right |
| `Mod+Shift+s/w/e` | Stacking/tabbed/toggle split layout |
| `Mod+Shift+f` | Toggle focused-pane fullscreen |
| `Mod+r` | Enter resize mode |
| `Mod+1..9` | Switch workspace |
| `Mod+Shift+1..9` | Move focused pane to workspace |
| `Mod+t` | Dump layout tree to `$TMPDIR/e3-tree.log` |

In resize mode, use `h/l` to shrink/grow width, `k/j` to shrink/grow height, and `Enter`, `Esc`, or `Mod+r` to return to normal mode.

## License

e3 is available under the [MIT License](LICENSE).
