package app

workspace_name :: proc(id: int) -> string {
	switch id {
	case 1:
		return "1"
	case 2:
		return "2"
	case 3:
		return "3"
	case 4:
		return "4"
	case 5:
		return "5"
	case 6:
		return "6"
	case 7:
		return "7"
	case 8:
		return "8"
	case 9:
		return "9"
	}

	return "?"
}

make_pane :: proc(app: ^App) -> ^Pane {
	pane := new(Pane)
	pane.id = app.next_pane_id
	pane.terminal.backend = .Libvterm
	pane.split_kind = .Split_Horizontal
	pane.split_active = false
	app.next_pane_id += 1
	return pane
}

make_pane_node :: proc(pane: ^Pane) -> ^Node {
	node := new(Node)
	node.kind = .Pane
	node.pane = pane
	return node
}

make_container_node :: proc(kind: Node_Kind) -> ^Node {
	node := new(Node)
	node.kind = kind
	node.children = make([dynamic]^Node)
	node.weights = make([dynamic]f32)
	return node
}

make_workspace :: proc(id: int) -> Workspace {
	return Workspace {
		id = id,
		name = workspace_name(id),
		default_split_kind = .Split_Horizontal,
	}
}

ensure_workspace_pane :: proc(app: ^App, workspace: ^Workspace) -> bool {
	if workspace == nil {
		return false
	}

	if workspace.root != nil {
		return true
	}

	pane := make_pane(app)
	pane.split_kind = workspace.default_split_kind
	pane.split_active = true
	workspace.root = make_pane_node(pane)
	workspace.focused_pane_id = pane.id
	return true
}

init_app :: proc(app: ^App) {
	app.workspaces = make([dynamic]Workspace)
	app.active_workspace_index = 0
	app.next_pane_id = 1

	append(&app.workspaces, make_workspace(1))
}

active_workspace :: proc(app: ^App) -> ^Workspace {
	if len(app.workspaces) == 0 {
		return nil
	}
	if app.active_workspace_index < 0 || app.active_workspace_index >= len(app.workspaces) {
		return nil
	}

	return &app.workspaces[app.active_workspace_index]
}

switch_workspace :: proc(app: ^App, id: int) -> bool {
	if id <= 0 {
		return false
	}

	active := active_workspace(app)
	if active != nil && active.id == id {
		return true
	}

	remove_empty_workspaces_except(app, id)

	for index in 0 ..< len(app.workspaces) {
		if app.workspaces[index].id == id {
			app.active_workspace_index = index
			return true
		}
	}

	workspace := make_workspace(id)
	insert_index := workspace_insert_index(app, id)
	append(&app.workspaces, workspace)
	for move_index := len(app.workspaces) - 1; move_index > insert_index; move_index -= 1 {
		app.workspaces[move_index] = app.workspaces[move_index - 1]
	}
	app.workspaces[insert_index] = workspace
	app.active_workspace_index = insert_index
	return true
}

workspace_insert_index :: proc(app: ^App, id: int) -> int {
	for index in 0 ..< len(app.workspaces) {
		if app.workspaces[index].id > id {
			return index
		}
	}
	return len(app.workspaces)
}

remove_empty_workspaces_except :: proc(app: ^App, keep_id: int) {
	previous_active_id := 0
	if active := active_workspace(app); active != nil {
		previous_active_id = active.id
	}

	index := 0
	for index < len(app.workspaces) {
		workspace := &app.workspaces[index]
		if workspace.id != keep_id && workspace.root == nil {
			ordered_remove(&app.workspaces, index)
			continue
		}
		index += 1
	}

	app.active_workspace_index = 0
	for index in 0 ..< len(app.workspaces) {
		if app.workspaces[index].id == previous_active_id {
			app.active_workspace_index = index
			return
		}
	}
}
