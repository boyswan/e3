# i3-Inspired Terminal Multiplexer Plan

## References

- Terminal backend: https://github.com/MauriceElliott/libghostty-odin
- Reference / ideas: https://github.com/RaphGL/TermCL
- ANSI escape abstraction: consider copying `termcl/raw` from TermCL. It is a small ~300 LOC file implementing the ANSI escape codes used by TermCL itself, and is intended to be copied into projects that only need that layer.
- Layout model: i3-style tree of workspaces, containers, and panes

## Goal

Build an Odin terminal multiplexer inspired by i3. The application should manage multiple workspaces. Each workspace owns a layout tree containing panes. Panes run terminal sessions backed by `libghostty-odin`.

## Core Concepts

### Application

- Owns global state.
- Tracks the active workspace.
- Handles input routing.
- Runs the main render/event loop.

### Workspace

- Represents an isolated layout tree.
- Has a stable id/name.
- Contains one root container.
- Tracks the focused pane within that workspace.

### Container

An i3-style layout node.

Container types:

- `SplitHorizontal`: children are arranged left-to-right.
- `SplitVertical`: children are arranged top-to-bottom.
- `Stacked`: one child visible at a time, with a tab-like selector.
- `Tabbed`: similar to stacked, but presented as tabs.
- `Pane`: leaf node containing a terminal session.

Each non-leaf container should contain:

- Layout kind.
- Child nodes.
- Focused child index.
- Split ratios or weights.

### Pane

- Leaf node in the workspace tree.
- Owns one terminal instance/session.
- Has a pane id.
- Stores its current bounds.
- Receives keyboard input when focused.
- Requests redraws when terminal output changes.

## Initial Data Model Sketch

```odin
Workspace :: struct {
    id: int,
    name: string,
    root: ^Node,
    focused_pane_id: int,
}

Node_Kind :: enum {
    Pane,
    Split_Horizontal,
    Split_Vertical,
    Stacked,
    Tabbed,
}

Node :: struct {
    kind: Node_Kind,
    parent: ^Node,

    // Used when kind == Pane
    pane: ^Pane,

    // Used for containers
    children: [dynamic]^Node,
    focused_child_index: int,
    weights: [dynamic]f32,
}

Pane :: struct {
    id: int,
    terminal: Terminal_Handle,
    x: int,
    y: int,
    width: int,
    height: int,
}
```

`Terminal_Handle` should be replaced with the actual type exposed by `libghostty-odin` once the dependency is integrated.

## Milestones

### 1. Project setup

- Add `libghostty-odin` as the terminal backend dependency.
- Review `TermCL` for useful ideas around input handling, terminal rendering, and application structure.
- Evaluate copying `termcl/raw` into this project as the ANSI escape-code layer instead of depending on all of TermCL.
- Confirm how Odin packages should be vendored or referenced in this project.
- Add a minimal build/run command once the dependency layout is known.

### 2. Basic terminal pane

- Create a single terminal pane.
- Spawn a shell inside it.
- Forward keyboard input to the terminal.
- Render terminal output to the screen.
- Resize the terminal when the application window/TTY size changes.

### 3. Workspace model

- Add workspace creation and switching.
- Start with numbered workspaces, matching i3 behavior.
- Keep each workspace's layout and focused pane independent.
- Implement commands:
  - Switch to workspace `1..9`.
  - Move focused pane to workspace `1..9`.

### 4. Layout tree

- Implement the `Node` tree.
- Support splitting the focused pane horizontally and vertically.
- Support focus movement between sibling panes.
- Recalculate pane bounds from the tree on every layout change.
- Keep layout code separate from terminal process code.

### 5. i3-like commands

Initial command set:

- Split horizontal.
- Split vertical.
- Focus left/right/up/down.
- Move pane left/right/up/down.
- Switch workspace.
- Move pane to workspace.
- Close focused pane.
- Toggle fullscreen pane.

Suggested keybinding style:

- Use a configurable modifier key similar to i3's `$mod`.
- Keep command handling separate from raw input parsing.

### 6. Rendering

- Render each visible pane into its assigned rectangle.
- Use a small ANSI escape abstraction for cursor movement, colors, clearing regions, and alternate screen handling. `termcl/raw` is the first candidate for this layer.
- Draw borders around panes.
- Highlight focused pane border.
- Draw workspace/status bar.
- Draw stacked/tabbed container labels later, after split layouts work.

### 7. Persistence / configuration

Later features:

- Config file for keybindings.
- Default shell command.
- Startup workspace layout.
- Theme colors.
- Border style.

## Suggested Implementation Order

1. Define app, workspace, node, and pane structs.
2. Get one terminal pane rendering with `libghostty-odin`.
3. Add workspace switching without splits.
4. Add horizontal/vertical split containers.
5. Add focus traversal.
6. Add pane movement.
7. Add workspace bar and borders.
8. Add stacked/tabbed layouts.
9. Add configuration.

## Current Implementation Notes

- Added initial Odin structs for `App`, `Workspace`, `Node`, and `Pane`.
- Added i3-style dynamic workspace initialization with numbered workspaces `1..9`: switching creates a workspace, empty workspaces disappear after switching away, and a workspace only persists once it has a pane.
- Workspaces now create their first pane only when opened or modified.
- Added basic active workspace switching.
- Added an initial command layer for split intent selection, opening panes, workspace switching, focus movement, and pane close.
- Added a cell-buffer renderer: layout writes into `Screen_Buffer`, then a backend presents the surface.
- Introduced a `Renderer` abstraction with `TTY` and `SDL3` backends so UI/layout rendering is no longer wired directly to terminal output.
- Added a first SDL3 backend using Odin's `vendor:sdl3`: it opens a resizable native window, maps the cell surface to SDL debug text, and presents the same mux UI through SDL.
- Reorganized source into focused packages instead of a single mux package: `src/app` for state/tree/commands/panes, `src/render` for surfaces/layout rendering, `src/renderer` for the backend façade, `src/sdl` for native SDL rendering/input, `src/tty` for terminal rendering/input/mode/size, and `src/input` for backend-agnostic input actions/bindings, with `src/main.odin` as the executable entrypoint.
- SDL3/native rendering is now the default; pass `--tty` or `--terminal` to use the terminal renderer.
- SDL3 mode now uses native SDL keyboard/text/window events instead of terminal stdin/raw mode: Alt keybindings map to existing mux commands, text and special keys route to the focused PTY, and window close quits.
- Improved SDL3 presentation: larger native cells/text and vector-drawn 1px separator/border lines instead of relying on tiny debug-text box-drawing glyphs.
- Improved the stepping-stone PTY terminal parser with basic CSI handling: cursor movement/positioning, clear screen/line, SGR/mode ignore, OSC skipping, bracketed paste mode ignore, and reverse index.
- Started libvterm integration: switched the Nix shell to `libvterm-neovim` (the C ABI with `vterm_new`/screen APIs) and added minimal Odin bindings in `src/terminal/libvterm.odin`.
- Added a terminal backend switch and made new panes use libvterm: PTY output now feeds `vterm_input_write`, damage is flushed, libvterm response bytes are drained back to the PTY, and rendering reads cells via `vterm_screen_get_cell`.
- Plumbed libvterm cell attributes into rendering: cells now carry optional RGB foreground/background colors, bold and reverse video are handled, SDL draws terminal backgrounds/text colors, and the TTY backend emits truecolor ANSI for terminal cell colors.
- Improved libvterm rendering fidelity: cells now preserve UTF-32 codepoints and encode them to UTF-8 at presentation time instead of replacing unknown glyphs with `?`; the focused pane cursor is drawn by inverting the libvterm cursor cell; libvterm state/screen default fg/bg colors are aligned to the renderer background, and the previous “explicit RGB black means default background” workaround was removed.
- Replaced SDL debug text with SDL3_ttf for native mode. SDL now resolves system fonts through Fontconfig or an explicit font path; no fonts are bundled.
- Added a basic persistent YAML-style config (`config.yaml`, also searches `odin-play.yaml` and XDG config paths) for native font, window foreground/background, terminal palette, SDL modifier key settings, and SDL keybindings instead of relying on environment variables.
- Tidied render backend structure: `src/renderer` now owns the small backend-agnostic renderer façade, SDL-specific state/rendering/font/cache/input/selection/clipboard code lives in `src/sdl`, and TTY output/input/mode/size code lives in `src/tty`.
- ANSI escape handling is isolated in the TTY backend instead of being scattered through render code.
- Renderer draws one outer frame, shared no-margin split separators, a colored focused-pane border, and a bottom workspace bar without a label.
- Focused pane insert hint is inactive until split mode is entered; active split-right colors the focused pane's right edge and active split-down colors its bottom edge.
- Screen line drawing now composes box-drawing junctions (`┬`, `├`, `┴`, etc.) from line connection masks instead of overwriting glyphs.
- Nested split separators extend to adjacent parent separators, so perpendicular split lines compose into proper junction glyphs instead of leaving disconnected `─`/`│` crossings.
- Added one-shot terminal size detection via `ioctl(TIOCGWINSZ)` with an `80x24` fallback, so the initial render uses the current terminal dimensions.
- Added a minimal interactive loop using alternate screen + raw terminal mode.
- Added initial Option/Alt-modified keybindings: `Opt+d` enters or switches to split-right mode, `Opt+Shift+d` enters or switches to split-down mode, `Opt+Enter` opens a pane only when the focused pane has active split mode, `Opt+w` closes the focused pane, `Opt+h/j/k/l` move focus, and `Opt+1..9` switch workspaces. Raw `q` remains as an emergency/dev quit key.
- Reworked focus movement to follow i3's tree-based behavior: climb ancestors until a matching split orientation is found, move to the adjacent sibling branch, then descend through that branch's saved focus path.
- Focus movement uses i3-style wrapping: at an edge, keep climbing first; if no higher-level move exists, wrap within the nearest matching split.
- Split context now follows i3 behavior with an explicit per-pane active state: entering split mode wraps the focused pane in a one-child split container when needed, changing split direction updates that context, and `Opt+Enter` consumes the active mode by inserting a new pane after the focused pane.
- Added layout cleanup helpers to remove empty containers, collapse one-child split containers, and repair weights/focus indexes. Same-orientation nested split containers are preserved because they can represent intentional i3 split context.
- Added focused pane close behavior; closing a pane removes it from the tree, closes its PTY master, selects a nearby fallback pane, and runs layout cleanup.
- Added `Opt+t` debug tree dumping to `/tmp/odin-play-tree.log`, including workspace state, node kind/order, focus indexes, bounds, and pane split mode state.
- The render loop recreates the screen buffer when the terminal size changes, currently checked before each redraw/input cycle.
- Terminal flushing no longer clears the screen on every frame; the alternate screen is cleared once on entry, then full frames overwrite cells in place to reduce flicker.
- Added basic i3-style split tree creation for horizontal and vertical splits.
- Added recursive layout calculation for split, stacked, tabbed, and pane nodes.
- Investigated `libghostty-odin`: it provides Odin bindings/wrappers for `libghostty-vt`, but requires building the Ghostty VT library separately with Zig.
- Added the first real terminal-pane vertical slice using PTY-backed `/bin/sh` processes, pane-local text grids, resize propagation, pane input routing, and basic output rendering.
- `Terminal_Handle` is no longer an empty stub; it now owns PTY state and a simple terminal grid. This is intentionally a stepping stone before replacing the text grid with `libghostty-vt` rendering.

## Open Questions

- Should this run directly in a terminal, or as a graphical window backed by Ghostty's terminal engine?
- How does `libghostty-odin` expose PTY/session lifecycle and rendering?
- Should panes share one renderer, or should each pane own its own terminal renderer state?
- What keybinding syntax should configuration use?
- Should workspace names be static numbers first, with named workspaces later?
