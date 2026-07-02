# e3

An experimental Odin terminal multiplexer inspired by i3.

`e3` opens terminal panes, arranges them in an i3-style layout tree, and supports numbered workspaces, split layouts, focus movement, pane movement, resize mode, and configurable keybindings. It runs as a native SDL3 window by default, with an optional terminal/TTY renderer.

## Requirements

The easiest way to get the required tools and libraries is with Nix:

```sh
nix develop
```

The development shell provides Odin, SDL3, SDL3_ttf, Fontconfig, and libvterm.

### macOS without Nix

Install the dependencies with Homebrew:

```sh
brew install odin sdl3 sdl3_ttf
```

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

macOS uses CoreText for `font.family` lookup, so Fontconfig is not required. If Option/Alt keybindings conflict with your keyboard layout, set `input.mod: "super"` in `config.yaml` to use Command instead.

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

## Configuration

Configuration is loaded from the first matching path:

1. `./config.yaml`
2. `./e3.yaml`
3. `$XDG_CONFIG_HOME/e3/config.yaml`
4. `~/.config/e3/config.yaml`

See `config.yaml` for the current options, including font settings, colors, pane styling, modifier key, and keybindings.

## Default keybindings

The default modifier is `Alt`.

| Binding | Action |
| --- | --- |
| `Alt+q` | Quit |
| `Alt+d` | Split/open to the right |
| `Alt+Shift+d` | Split/open down |
| `Alt+Enter` | Open pane in the active split context |
| `Alt+w` | Close focused pane |
| `Alt+h/j/k/l` | Focus left/down/up/right |
| `Alt+Shift+h/j/k/l` | Move pane left/down/up/right |
| `Alt+r` | Enter resize mode |
| `Alt+1..9` | Switch workspace |
| `Alt+t` | Dump layout tree to `/tmp/e3-tree.log` |

In resize mode, use `h/l` to shrink/grow width, `k/j` to shrink/grow height, and `Enter`, `Esc`, or `Alt+r` to return to normal mode.

## Notes

This project is a work in progress. See `plan.md` and `i3.md` for implementation notes and i3 behavior research.
