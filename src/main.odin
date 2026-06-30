package app

import "core:fmt"

print_node :: proc(node: ^Node, depth: int) {
	if node == nil {
		return
	}

	for _ in 0 ..< depth {
		fmt.print("  ")
	}

	switch node.kind {
	case .Pane:
		bounds := node.pane.bounds
		fmt.printf("pane id=%d bounds=(%d,%d %dx%d)\n", node.pane.id, bounds.x, bounds.y, bounds.width, bounds.height)
	case .Split_Horizontal, .Split_Vertical, .Stacked, .Tabbed:
		fmt.printf("container kind=%v focused_child=%d children=%d\n", node.kind, node.focused_child_index, len(node.children))
		for child in node.children {
			print_node(child, depth + 1)
		}
	}
}

main :: proc() {
	app: App
	init_app(&app)

	split_focused_pane(&app, true)
	split_focused_pane(&app, false)

	workspace := active_workspace(&app)
	layout_workspace(workspace, Rect{x = 0, y = 0, width = 120, height = 40})

	fmt.printf("workspace %s focused_pane=%d\n", workspace.name, workspace.focused_pane_id)
	print_node(workspace.root, 0)
}
