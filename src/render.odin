package app

render_app :: proc(buffer: ^Screen_Buffer, app: ^App, bounds: Rect) {
	workspace := active_workspace(app)
	if workspace == nil {
		return
	}

	screen_clear(buffer)

	content_bounds := Rect {
		x = bounds.x,
		y = bounds.y,
		width = bounds.width,
		height = bounds.height - 1,
	}

	layout_workspace(workspace, content_bounds)
	render_split_separators(buffer, workspace.root)
	screen_draw_box(buffer, content_bounds)
	render_focused_pane_border(buffer, workspace, content_bounds)
	render_pane_labels(buffer, workspace.root, workspace.focused_pane_id)
	render_workspace_bar(buffer, app, Rect{x = bounds.x, y = bounds.y + bounds.height - 1, width = bounds.width, height = 1})
}

render_workspace_bar :: proc(buffer: ^Screen_Buffer, app: ^App, bounds: Rect) {
	cursor_x := bounds.x

	for index in 0 ..< len(app.workspaces) {
		workspace := &app.workspaces[index]
		if index == app.active_workspace_index {
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "[")
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, workspace.name, true)
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "] ")
		} else {
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, " ")
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, workspace.name)
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "  ")
		}
	}
}

render_split_separators :: proc(buffer: ^Screen_Buffer, node: ^Node) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		return
	case .Split_Horizontal:
		for child in node.children {
			render_split_separators(buffer, child)
		}

		bounds, ok := node_bounds(node)
		if !ok {
			return
		}

		for index in 0 ..< len(node.children) - 1 {
			child_bounds, child_ok := node_bounds(node.children[index])
			if child_ok {
				screen_draw_vertical_line(buffer, child_bounds.x + child_bounds.width, bounds.y, bounds.height)
			}
		}
	case .Split_Vertical:
		for child in node.children {
			render_split_separators(buffer, child)
		}

		bounds, ok := node_bounds(node)
		if !ok {
			return
		}

		for index in 0 ..< len(node.children) - 1 {
			child_bounds, child_ok := node_bounds(node.children[index])
			if child_ok {
				screen_draw_horizontal_line(buffer, bounds.x, child_bounds.y + child_bounds.height, bounds.width)
			}
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		render_split_separators(buffer, node.children[index])
	}
}

render_pane_labels :: proc(buffer: ^Screen_Buffer, node: ^Node, focused_pane_id: int) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane != nil {
			render_pane_label(buffer, node.pane, node.pane.id == focused_pane_id)
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			render_pane_labels(buffer, child, focused_pane_id)
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		render_pane_labels(buffer, node.children[index], focused_pane_id)
	}
}

render_pane_label :: proc(buffer: ^Screen_Buffer, pane: ^Pane, focused: bool) {
	bounds := pane.bounds
	if bounds.width <= 3 || bounds.height <= 2 {
		return
	}

	cursor_x := bounds.x + 1
	cursor_x = screen_put_text(buffer, cursor_x, bounds.y + 1, "pane ")
	screen_put_int(buffer, cursor_x, bounds.y + 1, pane.id)
}

render_focused_pane_border :: proc(buffer: ^Screen_Buffer, workspace: ^Workspace, content_bounds: Rect) {
	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.pane == nil {
		return
	}

	bounds := focused.pane.bounds
	left := bounds.x
	right := bounds.x + bounds.width
	top := bounds.y
	bottom := bounds.y + bounds.height

	if right >= content_bounds.x + content_bounds.width {
		right = content_bounds.x + content_bounds.width - 1
	}
	if bottom >= content_bounds.y + content_bounds.height {
		bottom = content_bounds.y + content_bounds.height - 1
	}

	for x in left ..= right {
		screen_set_color(buffer, x, top, .Focused)
		screen_set_color(buffer, x, bottom, .Focused)
	}

	for y in top ..= bottom {
		screen_set_color(buffer, left, y, .Focused)
		screen_set_color(buffer, right, y, .Focused)
	}
}

node_bounds :: proc(node: ^Node) -> (Rect, bool) {
	if node == nil {
		return Rect{}, false
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil {
			return Rect{}, false
		}

		return node.pane.bounds, true
	case .Split_Horizontal, .Split_Vertical:
		if len(node.children) == 0 {
			return Rect{}, false
		}

		bounds, ok := node_bounds(node.children[0])
		if !ok {
			return Rect{}, false
		}

		for index in 1 ..< len(node.children) {
			child_bounds, child_ok := node_bounds(node.children[index])
			if child_ok {
				bounds = rect_union(bounds, child_bounds)
			}
		}

		return bounds, true
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return Rect{}, false
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		return node_bounds(node.children[index])
	}

	return Rect{}, false
}

rect_union :: proc(a: Rect, b: Rect) -> Rect {
	left := min_int(a.x, b.x)
	top := min_int(a.y, b.y)
	right := max_int(a.x + a.width, b.x + b.width)
	bottom := max_int(a.y + a.height, b.y + b.height)

	return Rect {
		x = left,
		y = top,
		width = right - left,
		height = bottom - top,
	}
}

min_int :: proc(a: int, b: int) -> int {
	if a < b {
		return a
	}

	return b
}

max_int :: proc(a: int, b: int) -> int {
	if a > b {
		return a
	}

	return b
}
