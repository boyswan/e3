package app

import "core:fmt"
import "core:os"
import "core:strings"

DEBUG_TREE_PATH :: "/tmp/odin-play-tree.log"

dump_tree :: proc(app: ^App) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintfln(&builder, "odin-play tree dump")
	fmt.sbprintfln(&builder, "active_workspace_index=%d next_pane_id=%d", app.active_workspace_index, app.next_pane_id)
	fmt.sbprintfln(&builder, "")

	for index in 0 ..< len(app.workspaces) {
		workspace := &app.workspaces[index]
		active_marker := " "
		if index == app.active_workspace_index {
			active_marker = "*"
		}

		fmt.sbprintfln(
			&builder,
			"%s workspace id=%d name=%s focused_pane=%d root=%p",
			active_marker,
			workspace.id,
			workspace.name,
			workspace.focused_pane_id,
			workspace.root,
		)

		dump_node(&builder, workspace.root, 1, workspace.focused_pane_id)
		fmt.sbprintfln(&builder, "")
	}

	return os.write_entire_file(DEBUG_TREE_PATH, strings.to_string(builder)) == nil
}

dump_node :: proc(builder: ^strings.Builder, node: ^Node, depth: int, focused_pane_id: int) {
	write_indent(builder, depth)
	if node == nil {
		fmt.sbprintfln(builder, "nil")
		return
	}

	fmt.sbprintf(
		builder,
		"node=%p kind=%v parent=%p focused_child=%d children=%d weights=%d",
		node,
		node.kind,
		node.parent,
		node.focused_child_index,
		len(node.children),
		len(node.weights),
	)

	if node.kind == .Pane && node.pane != nil {
		pane := node.pane
		focused_marker := " "
		if pane.id == focused_pane_id {
			focused_marker = "*"
		}

		fmt.sbprintf(
			builder,
			" %s pane_id=%d bounds=(%d,%d %dx%d) split_active=%v split_kind=%v",
			focused_marker,
			pane.id,
			pane.bounds.x,
			pane.bounds.y,
			pane.bounds.width,
			pane.bounds.height,
			pane.split_active,
			pane.split_kind,
		)
	}

	fmt.sbprintfln(builder, "")

	for index in 0 ..< len(node.children) {
		write_indent(builder, depth + 1)
		weight := f32(0)
		if index < len(node.weights) {
			weight = node.weights[index]
		}
		fmt.sbprintfln(builder, "child[%d] weight=%f", index, weight)
		dump_node(builder, node.children[index], depth + 2, focused_pane_id)
	}
}

write_indent :: proc(builder: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(builder, "  ")
	}
}
