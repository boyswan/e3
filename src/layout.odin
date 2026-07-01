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

first_focusable_pane :: proc(node: ^Node) -> ^Pane {
	if node == nil {
		return nil
	}

	switch node.kind {
	case .Pane:
		return node.pane
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			pane := first_focusable_pane(child)
			if pane != nil {
				return pane
			}
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return nil
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		return first_focusable_pane(node.children[index])
	}

	return nil
}

last_focusable_pane :: proc(node: ^Node) -> ^Pane {
	if node == nil {
		return nil
	}

	switch node.kind {
	case .Pane:
		return node.pane
	case .Split_Horizontal, .Split_Vertical:
		for index := len(node.children) - 1; index >= 0; index -= 1 {
			pane := last_focusable_pane(node.children[index])
			if pane != nil {
				return pane
			}
		}
	case .Stacked, .Tabbed:
		if len(node.children) == 0 {
			return nil
		}

		index := node.focused_child_index
		if index < 0 || index >= len(node.children) {
			index = 0
		}

		return last_focusable_pane(node.children[index])
	}

	return nil
}

descend_focused :: proc(node: ^Node) -> ^Node {
	current := node
	if current == nil {
		return nil
	}

	for current.kind != .Pane {
		if len(current.children) == 0 {
			return nil
		}

		index := current.focused_child_index
		if index < 0 || index >= len(current.children) {
			index = 0
		}

		current = current.children[index]
	}

	return current
}

focus_node :: proc(workspace: ^Workspace, node: ^Node) -> bool {
	if workspace == nil || node == nil {
		return false
	}

	target := descend_focused(node)
	if target == nil || target.pane == nil {
		return false
	}

	workspace.focused_pane_id = target.pane.id

	child := target
	parent := child.parent
	for parent != nil {
		index := find_child_index(parent, child)
		if index < 0 {
			return false
		}

		parent.focused_child_index = index
		child = parent
		parent = parent.parent
	}

	return true
}

focus_pane :: proc(workspace: ^Workspace, pane: ^Pane) -> bool {
	if workspace == nil || pane == nil {
		return false
	}

	node := find_focused_node(workspace.root, pane.id)
	return focus_node(workspace, node)
}

insert_child_after :: proc(parent: ^Node, existing: ^Node, child: ^Node) -> bool {
	if parent == nil || child == nil {
		return false
	}

	index := find_child_index(parent, existing)
	if index < 0 {
		return false
	}

	insert_index := index + 1
	append(&parent.children, child)
	append(&parent.weights, 1.0)

	for move_index := len(parent.children) - 1; move_index > insert_index; move_index -= 1 {
		parent.children[move_index] = parent.children[move_index - 1]
		parent.weights[move_index] = parent.weights[move_index - 1]
	}

	parent.children[insert_index] = child
	parent.weights[insert_index] = 1.0
	child.parent = parent
	parent.focused_child_index = insert_index
	return true
}

apply_split_context :: proc(app: ^App, kind: Node_Kind) -> bool {
	workspace := active_workspace(app)
	if !ensure_workspace_pane(app, workspace) {
		return false
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.kind != .Pane || focused.pane == nil {
		return false
	}

	focused.pane.split_kind = kind
	focused.pane.split_active = true

	parent := focused.parent
	if parent == nil {
		container := make_container_node(kind)
		container.parent = nil
		focused.parent = container
		append(&container.children, focused)
		append(&container.weights, 1.0)
		container.focused_child_index = 0
		workspace.root = container
		return focus_node(workspace, focused)
	}

	if is_split_kind(parent.kind) && len(parent.children) == 1 {
		parent.kind = kind
		return focus_node(workspace, focused)
	}

	container := make_container_node(kind)
	container.parent = parent
	container.focused_child_index = 0

	index := find_child_index(parent, focused)
	if index < 0 {
		return false
	}

	parent.children[index] = container
	focused.parent = container
	append(&container.children, focused)
	append(&container.weights, 1.0)
	parent.focused_child_index = index

	return focus_node(workspace, focused)
}

open_pane :: proc(app: ^App) -> bool {
	workspace := active_workspace(app)
	if workspace == nil {
		return false
	}

	if workspace.root == nil {
		return ensure_workspace_pane(app, workspace)
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.kind != .Pane || focused.pane == nil || !focused.pane.split_active {
		return false
	}

	parent := focused.parent
	if parent == nil {
		if !apply_split_context(app, focused.pane.split_kind) {
			return false
		}

		focused = find_focused_node(workspace.root, workspace.focused_pane_id)
		if focused == nil || focused.pane == nil {
			return false
		}
		parent = focused.parent
	}

	new_pane := make_pane(app)
	new_node := make_pane_node(new_pane)
	focused.pane.split_active = false
	if !insert_child_after(parent, focused, new_node) {
		return false
	}

	cleanup_workspace(workspace)
	return focus_pane(workspace, new_pane)
}

split_focused_pane :: proc(app: ^App, horizontal: bool) -> bool {
	workspace := active_workspace(app)
	if !ensure_workspace_pane(app, workspace) {
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
		if !insert_child_after(parent, focused, new_node) {
			return false
		}

		cleanup_workspace(workspace)
		return focus_pane(workspace, new_pane)
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

	cleanup_workspace(workspace)
	return focus_pane(workspace, new_pane)
}

close_focused_pane :: proc(app: ^App) -> bool {
	workspace := active_workspace(app)
	if workspace == nil || workspace.root == nil {
		return false
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil || focused.kind != .Pane {
		return false
	}

	parent := focused.parent
	if parent == nil {
		workspace.root = nil
		workspace.focused_pane_id = 0
		return true
	}

	index := find_child_index(parent, focused)
	if index < 0 {
		return false
	}

	ordered_remove(&parent.children, index)
	if index < len(parent.weights) {
		ordered_remove(&parent.weights, index)
	}

	if len(parent.children) > 0 {
		focus_index := index
		if focus_index >= len(parent.children) {
			focus_index = len(parent.children) - 1
		}

		parent.focused_child_index = focus_index
		fallback := descend_focused(parent.children[focus_index])
		if fallback != nil && fallback.pane != nil {
			workspace.focused_pane_id = fallback.pane.id
		}
	}

	cleanup_workspace(workspace)
	return true
}

orientation_from_direction :: proc(direction: Direction) -> Node_Kind {
	switch direction {
	case .Left, .Right:
		return .Split_Horizontal
	case .Up, .Down:
		return .Split_Vertical
	}

	return .Split_Horizontal
}

is_previous_direction :: proc(direction: Direction) -> bool {
	return direction == .Left || direction == .Up
}

navigation_kind :: proc(kind: Node_Kind) -> (Node_Kind, bool) {
	switch kind {
	case .Split_Horizontal, .Tabbed:
		return .Split_Horizontal, true
	case .Split_Vertical, .Stacked:
		return .Split_Vertical, true
	case .Pane:
		return .Pane, false
	}

	return .Pane, false
}

cleanup_workspace :: proc(workspace: ^Workspace) {
	if workspace == nil || workspace.root == nil {
		return
	}

	workspace.root = cleanup_node(workspace.root)
	if workspace.root != nil {
		workspace.root.parent = nil
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused != nil {
		focus_node(workspace, focused)
		return
	}

	fallback := descend_focused(workspace.root)
	if fallback != nil {
		focus_node(workspace, fallback)
		return
	}

	workspace.focused_pane_id = 0
}

cleanup_node :: proc(node: ^Node) -> ^Node {
	if node == nil || node.kind == .Pane {
		return node
	}

	index := 0
	for index < len(node.children) {
		child := cleanup_node(node.children[index])
		if child == nil {
			ordered_remove(&node.children, index)
			if index < len(node.weights) {
				ordered_remove(&node.weights, index)
			}
			continue
		}

		child.parent = node
		node.children[index] = child
		index += 1
	}

	if len(node.children) == 0 {
		return nil
	}

	if is_split_kind(node.kind) {
		if len(node.children) == 1 && !node_has_active_split_context(node) {
			child := node.children[0]
			child.parent = node.parent
			return child
		}
	}

	repair_container_focus_and_weights(node)
	return node
}

is_split_kind :: proc(kind: Node_Kind) -> bool {
	return kind == .Split_Horizontal || kind == .Split_Vertical
}

node_has_active_split_context :: proc(node: ^Node) -> bool {
	focused := descend_focused(node)
	return focused != nil && focused.pane != nil && focused.pane.split_active
}

merge_same_kind_children :: proc(node: ^Node) {
	if node == nil || !is_split_kind(node.kind) {
		return
	}

	index := 0
	for index < len(node.children) {
		child := node.children[index]
		if child == nil || child.kind != node.kind {
			index += 1
			continue
		}

		ordered_remove(&node.children, index)
		if index < len(node.weights) {
			ordered_remove(&node.weights, index)
		}

		insert_index := index
		for grandchild in child.children {
			grandchild.parent = node
			append(&node.children, grandchild)
			append(&node.weights, 1.0)

			for move_index := len(node.children) - 1; move_index > insert_index; move_index -= 1 {
				node.children[move_index] = node.children[move_index - 1]
				node.weights[move_index] = node.weights[move_index - 1]
			}

			node.children[insert_index] = grandchild
			node.weights[insert_index] = 1.0
			insert_index += 1
		}
	}
}

repair_container_focus_and_weights :: proc(node: ^Node) {
	if node == nil || node.kind == .Pane {
		return
	}

	for len(node.weights) < len(node.children) {
		append(&node.weights, 1.0)
	}
	for len(node.weights) > len(node.children) {
		pop(&node.weights)
	}

	for index in 0 ..< len(node.weights) {
		if node.weights[index] <= 0 {
			node.weights[index] = 1.0
		}
	}

	if len(node.children) == 0 {
		node.focused_child_index = 0
		return
	}

	if node.focused_child_index < 0 || node.focused_child_index >= len(node.children) {
		node.focused_child_index = 0
	}
}

focus_direction :: proc(app: ^App, direction: Direction) -> bool {
	workspace := active_workspace(app)
	if !ensure_workspace_pane(app, workspace) {
		return false
	}

	focused := find_focused_node(workspace.root, workspace.focused_pane_id)
	if focused == nil {
		return false
	}

	wanted_kind := orientation_from_direction(direction)
	previous := is_previous_direction(direction)
	current := focused
	wrap_candidate: ^Node

	for current.parent != nil {
		parent := current.parent
		parent_kind, ok := navigation_kind(parent.kind)
		if ok && parent_kind == wanted_kind && len(parent.children) > 1 {
			index := find_child_index(parent, current)
			if index < 0 {
				return false
			}

			next_index := index + 1
			if previous {
				next_index = index - 1
			}

			if next_index >= 0 && next_index < len(parent.children) {
				return focus_node(workspace, parent.children[next_index])
			}

			if wrap_candidate == nil {
				wrap_index := 0
				if previous {
					wrap_index = len(parent.children) - 1
				}

				wrap_candidate = parent.children[wrap_index]
			}
		}

		current = parent
	}

	if wrap_candidate != nil {
		return focus_node(workspace, wrap_candidate)
	}

	return false
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
