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
	workspace.root = make_pane_node(pane)
	workspace.focused_pane_id = pane.id
	return true
}

init_app :: proc(app: ^App) {
	app.workspaces = make([dynamic]Workspace)
	app.active_workspace_index = 0
	app.next_pane_id = 1

	for id in 1 ..= 9 {
		workspace := make_workspace(id)
		append(&app.workspaces, workspace)
	}
}

active_workspace :: proc(app: ^App) -> ^Workspace {
	if len(app.workspaces) == 0 {
		return nil
	}

	return &app.workspaces[app.active_workspace_index]
}

switch_workspace :: proc(app: ^App, id: int) -> bool {
	for index in 0 ..< len(app.workspaces) {
		if app.workspaces[index].id == id {
			app.active_workspace_index = index
			return ensure_workspace_pane(app, &app.workspaces[index])
		}
	}

	return false
}
