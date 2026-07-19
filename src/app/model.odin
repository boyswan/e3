package app

import "core:time"
import vt "../terminal"

Terminal_Backend :: enum {
	Simple,
	Ghostty,
}

Terminal_Handle :: struct {
	backend: Terminal_Backend,
	active:  bool,
	pty_fd:             int,
	pid:                int,
	width:              int,
	height:             int,
	spawn_error_logged: bool,

	ghostty:      vt.GhosttyTerminal,
	render_state: vt.GhosttyRenderState,
	row_iterator: vt.GhosttyRenderStateRowIterator,
	row_cells:    vt.GhosttyRenderStateRowCells,

	title_cache:        string,
	title_refresh_tick: time.Tick,
	title_initialized:  bool,

	cursor_x: int,
	cursor_y: int,
	cells:              []byte,
	escape:             int,
	escape_params:      [16]int,
	escape_param_count: int,
	escape_value:       int,
	escape_has_value:   bool,
	escape_private:     bool,
}

Rect :: struct {
	x:      int,
	y:      int,
	width:  int,
	height: int,
}

Pane :: struct {
	id:           int,
	terminal:     Terminal_Handle,
	bounds:       Rect,
	split_kind:   Node_Kind,
	split_active: bool,
}

Node_Kind :: enum {
	Pane,
	Split_Horizontal,
	Split_Vertical,
	Stacked,
	Tabbed,
}

Direction :: enum {
	Left,
	Right,
	Up,
	Down,
}

Node :: struct {
	kind:   Node_Kind,
	parent: ^Node,
	bounds: Rect,
	deco_bounds: Rect,

	// Leaf node state.
	pane: ^Pane,

	// Container node state.
	children:            [dynamic]^Node,
	focused_child_index: int,
	focus_order:         [dynamic]^Node,
	weights:             [dynamic]f32,
	last_split_kind:     Node_Kind,
}

Workspace :: struct {
	id:              int,
	name:            string,
	root:            ^Node,
	focused_pane_id: int,
	default_split_kind: Node_Kind,
}

App :: struct {
	workspaces:             [dynamic]Workspace,
	active_workspace_index: int,
	next_pane_id:           int,
}
