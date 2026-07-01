package app

Command_Kind :: enum {
	Split_Horizontal,
	Split_Vertical,
	Switch_Workspace,
	Focus,
}

Command :: struct {
	kind:         Command_Kind,
	workspace_id: int,
	direction:    Direction,
}

command_split_horizontal :: proc() -> Command {
	return Command{kind = .Split_Horizontal}
}

command_split_vertical :: proc() -> Command {
	return Command{kind = .Split_Vertical}
}

command_switch_workspace :: proc(id: int) -> Command {
	return Command{kind = .Switch_Workspace, workspace_id = id}
}

command_focus :: proc(direction: Direction) -> Command {
	return Command{kind = .Focus, direction = direction}
}

execute_command :: proc(app: ^App, command: Command) -> bool {
	switch command.kind {
	case .Split_Horizontal:
		return split_focused_pane(app, true)
	case .Split_Vertical:
		return split_focused_pane(app, false)
	case .Switch_Workspace:
		return switch_workspace(app, command.workspace_id)
	case .Focus:
		return focus_direction(app, command.direction)
	}

	return false
}
