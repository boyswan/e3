package app

split_kind_from_direction :: proc(horizontal: bool) -> Node_Kind {
	if horizontal {
		return .Split_Horizontal
	}

	return .Split_Vertical
}

find_focused_node :: proc(node: ^Node, pane_id: int) -> ^Node {
	if node == nil {
		return nil
	}

	if node.kind == .Pane {
		if node.pane != nil && node.pane.id == pane_id {
			return node
		}

		return nil
	}

	for child in node.children {
		found := find_focused_node(child, pane_id)
		if found != nil {
			return found
		}
	}

	return nil
}

find_child_index :: proc(parent: ^Node, child: ^Node) -> int {
	if parent == nil {
		return -1
	}

	for index in 0 ..< len(parent.children) {
		if parent.children[index] == child {
			return index
		}
	}

	return -1
}

split_focused_pane :: proc(app: ^App, horizontal: bool) -> bool {
	workspace := active_workspace(app)
	if workspace == nil {
		return false
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.kind != .Pane {
		return false
	}

	kind := split_kind_from_direction(horizontal)
	new_pane := make_pane(app)
	new_node := make_pane_node(new_pane)

	parent := focused.parent
	if parent != nil && parent.kind == kind {
		new_node.parent = parent
		append(&parent.children, new_node)
		append(&parent.weights, 1.0)
		parent.focused_child_index = len(parent.children) - 1
		workspace.focused_pane_id = new_pane.id
		return true
	}

	container := make_container_node(kind)
	container.parent = parent

	focused.parent = container
	new_node.parent = container

	append(&container.children, focused)
	append(&container.children, new_node)
	append(&container.weights, 1.0)
	append(&container.weights, 1.0)
	container.focused_child_index = 1

	if parent == nil {
		workspace.root = container
	} else {
		index := find_child_index(parent, focused)
		if index < 0 {
			return false
		}

		parent.children[index] = container
		parent.focused_child_index = index
	}

	workspace.focused_pane_id = new_pane.id
	return true
}

layout_workspace :: proc(workspace: ^Workspace, bounds: Rect) {
	if workspace == nil || workspace.root == nil {
		return
	}

	layout_node(workspace.root, bounds)
}

layout_node :: proc(node: ^Node, bounds: Rect) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane != nil {
			node.pane.bounds = bounds
		}
	case .Split_Horizontal:
		layout_split_horizontal(node, bounds)
	case .Split_Vertical:
		layout_split_vertical(node, bounds)
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		layout_node(node.children[index], bounds)
	}
}

layout_split_horizontal :: proc(node: ^Node, bounds: Rect) {
	child_count := len(node.children)
	if child_count == 0 {
		return
	}

	remaining_width := bounds.width
	x := bounds.x

	for index in 0 ..< child_count {
		child_width := bounds.width / child_count
		if index == child_count - 1 {
			child_width = remaining_width
		}

		layout_node(node.children[index], Rect {
			x = x,
			y = bounds.y,
			width = child_width,
			height = bounds.height,
		})

		x += child_width
		remaining_width -= child_width
	}
}

layout_split_vertical :: proc(node: ^Node, bounds: Rect) {
	child_count := len(node.children)
	if child_count == 0 {
		return
	}

	remaining_height := bounds.height
	y := bounds.y

	for index in 0 ..< child_count {
		child_height := bounds.height / child_count
		if index == child_count - 1 {
			child_height = remaining_height
		}

		layout_node(node.children[index], Rect {
			x = bounds.x,
			y = y,
			width = bounds.width,
			height = child_height,
		})

		y += child_height
		remaining_height -= child_height
	}
}
