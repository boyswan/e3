package app

Command_Kind :: enum {
	Set_Split_Right,
	Set_Split_Down,
	Open_Pane,
	Switch_Workspace,
	Focus,
	Resize_Grow_Width,
	Resize_Shrink_Width,
	Resize_Grow_Height,
	Resize_Shrink_Height,
	Move_Pane,
	Layout_Toggle_Split,
	Layout_Tabbed,
	Close_Pane,
	Dump_Tree,
}

Command :: struct {
	kind:         Command_Kind,
	workspace_id: int,
	direction:    Direction,
}

command_set_split_right :: proc() -> Command {
	return Command{kind = .Set_Split_Right}
}

command_set_split_down :: proc() -> Command {
	return Command{kind = .Set_Split_Down}
}

command_open_pane :: proc() -> Command {
	return Command{kind = .Open_Pane}
}

command_switch_workspace :: proc(id: int) -> Command {
	return Command{kind = .Switch_Workspace, workspace_id = id}
}

command_focus :: proc(direction: Direction) -> Command {
	return Command{kind = .Focus, direction = direction}
}

command_resize_grow_width :: proc() -> Command {
	return Command{kind = .Resize_Grow_Width}
}

command_resize_shrink_width :: proc() -> Command {
	return Command{kind = .Resize_Shrink_Width}
}

command_resize_grow_height :: proc() -> Command {
	return Command{kind = .Resize_Grow_Height}
}

command_resize_shrink_height :: proc() -> Command {
	return Command{kind = .Resize_Shrink_Height}
}

command_move_pane :: proc(direction: Direction) -> Command {
	return Command{kind = .Move_Pane, direction = direction}
}

command_layout_toggle_split :: proc() -> Command {
	return Command{kind = .Layout_Toggle_Split}
}

command_layout_tabbed :: proc() -> Command {
	return Command{kind = .Layout_Tabbed}
}

command_close_pane :: proc() -> Command {
	return Command{kind = .Close_Pane}
}

command_dump_tree :: proc() -> Command {
	return Command{kind = .Dump_Tree}
}

execute_command :: proc(app: ^App, command: Command) -> bool {
	switch command.kind {
	case .Set_Split_Right:
		return apply_split_context(app, .Split_Horizontal)
	case .Set_Split_Down:
		return apply_split_context(app, .Split_Vertical)
	case .Open_Pane:
		return open_pane(app)
	case .Switch_Workspace:
		return switch_workspace(app, command.workspace_id)
	case .Focus:
		return focus_direction(app, command.direction)
	case .Resize_Grow_Width:
		return resize_dimension(app, .Split_Horizontal, 0.10)
	case .Resize_Shrink_Width:
		return resize_dimension(app, .Split_Horizontal, -0.10)
	case .Resize_Grow_Height:
		return resize_dimension(app, .Split_Vertical, 0.10)
	case .Resize_Shrink_Height:
		return resize_dimension(app, .Split_Vertical, -0.10)
	case .Move_Pane:
		return move_pane_direction(app, command.direction)
	case .Layout_Toggle_Split:
		return layout_toggle_split(app)
	case .Layout_Tabbed:
		return layout_tabbed(app)
	case .Close_Pane:
		return close_focused_pane(app)
	case .Dump_Tree:
		return dump_tree(app)
	}

	return false
}
