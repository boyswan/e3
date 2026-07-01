package render

import domain "../app"

render_app :: proc(buffer: ^Screen_Buffer, state: ^domain.App, bounds: domain.Rect) {
	workspace := domain.active_workspace(state)
	if workspace == nil {
		return
	}

	screen_clear(buffer)

	content_bounds := domain.Rect {
		x = bounds.x,
		y = bounds.y,
		width = bounds.width,
		height = bounds.height - 1,
	}

	domain.layout_workspace(workspace, content_bounds)
	domain.sync_pane_terminals(workspace.root)
	render_split_separators(buffer, workspace.root)
	screen_draw_box(buffer, content_bounds)
	render_focused_pane_border(buffer, state, workspace, content_bounds)
	render_pane_labels(buffer, workspace.root, workspace.focused_pane_id)
	render_workspace_bar(buffer, state, domain.Rect{x = bounds.x, y = bounds.y + bounds.height - 1, width = bounds.width, height = 1})
}

render_workspace_bar :: proc(buffer: ^Screen_Buffer, state: ^domain.App, bounds: domain.Rect) {
	cursor_x := bounds.x

	for index in 0 ..< len(state.workspaces) {
		workspace := &state.workspaces[index]
		if index == state.active_workspace_index {
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "[")
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, workspace.name, true)
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "] ")
		} else {
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, " ")
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, workspace.name)
			cursor_x = screen_put_text(buffer, cursor_x, bounds.y, "  ")
		}
	}

	split_kind, has_split_kind := focused_insertion_kind(state)
	if has_split_kind {
		cursor_x = screen_put_text(buffer, cursor_x, bounds.y, " split:")
		if split_kind == .Split_Horizontal {
			screen_put_text(buffer, cursor_x, bounds.y, "right", true, .Split_Hint)
		} else {
			screen_put_text(buffer, cursor_x, bounds.y, "down", true, .Split_Hint)
		}
	}
}

render_split_separators :: proc(buffer: ^Screen_Buffer, node: ^domain.Node) {
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

		line_y := bounds.y
		line_height := bounds.height
		if node.parent != nil && node.parent.kind == .Split_Vertical {
			index := domain.find_child_index(node.parent, node)
			if index >= 0 && index < len(node.parent.children) - 1 {
				line_height += 1
			}
		}

		for index in 0 ..< len(node.children) - 1 {
			child_bounds, child_ok := node_bounds(node.children[index])
			if child_ok {
				screen_draw_vertical_line(buffer, child_bounds.x + child_bounds.width, line_y, line_height)
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

		line_x := bounds.x
		line_width := bounds.width

		for index in 0 ..< len(node.children) - 1 {
			child_bounds, child_ok := node_bounds(node.children[index])
			if child_ok {
				screen_draw_horizontal_line(buffer, line_x, child_bounds.y + child_bounds.height, line_width)
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

render_pane_labels :: proc(buffer: ^Screen_Buffer, node: ^domain.Node, focused_pane_id: int) {
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

render_pane_label :: proc(buffer: ^Screen_Buffer, pane: ^domain.Pane, focused: bool) {
	bounds := pane.bounds
	if bounds.width <= 3 || bounds.height <= 2 {
		return
	}

	render_terminal_contents(buffer, pane)
}

render_focused_pane_border :: proc(buffer: ^Screen_Buffer, state: ^domain.App, workspace: ^domain.Workspace, content_bounds: domain.Rect) {
	focused := domain.find_focused_node(workspace.root, workspace.focused_pane_id)
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

	split_kind, has_split_kind := focused_node_insertion_kind(focused)
	if !has_split_kind {
		return
	}

	if split_kind == .Split_Vertical {
		for x in left ..= right {
			screen_set_color(buffer, x, bottom, .Split_Hint)
		}
		return
	}

	for y in top ..= bottom {
		screen_set_color(buffer, right, y, .Split_Hint)
	}
}

focused_insertion_kind :: proc(state: ^domain.App) -> (domain.Node_Kind, bool) {
	workspace := domain.active_workspace(state)
	if workspace == nil {
		return .Pane, false
	}

	focused := domain.find_focused_node(workspace.root, workspace.focused_pane_id)
	return focused_node_insertion_kind(focused)
}

focused_node_insertion_kind :: proc(focused: ^domain.Node) -> (domain.Node_Kind, bool) {
	if focused == nil || focused.pane == nil || !focused.pane.split_active {
		return .Pane, false
	}

	return focused.pane.split_kind, true
}

node_bounds :: proc(node: ^domain.Node) -> (domain.Rect, bool) {
	if node == nil {
		return domain.Rect{}, false
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil {
			return domain.Rect{}, false
		}

		return node.pane.bounds, true
	case .Split_Horizontal, .Split_Vertical:
		if len(node.children) == 0 {
			return domain.Rect{}, false
		}

		bounds, ok := node_bounds(node.children[0])
		if !ok {
			return domain.Rect{}, false
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
			return domain.Rect{}, false
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		return node_bounds(node.children[index])
	}

	return domain.Rect{}, false
}

rect_union :: proc(a: domain.Rect, b: domain.Rect) -> domain.Rect {
	left := min_int(a.x, b.x)
	top := min_int(a.y, b.y)
	right := max_int(a.x + a.width, b.x + b.width)
	bottom := max_int(a.y + a.height, b.y + b.height)

	return domain.Rect {
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
