package app

Terminal_Handle :: struct {
	active:   bool,
	pty_fd:   int,
	pid:      int,
	width:    int,
	height:   int,
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

	// Leaf node state.
	pane: ^Pane,

	// Container node state.
	children:            [dynamic]^Node,
	focused_child_index: int,
	weights:             [dynamic]f32,
}

Workspace :: struct {
	id:              int,
	name:            string,
	root:            ^Node,
	focused_pane_id: int,
}

App :: struct {
	workspaces:             [dynamic]Workspace,
	active_workspace_index: int,
	next_pane_id:           int,
}
