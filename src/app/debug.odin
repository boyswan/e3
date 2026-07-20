package app

import "core:fmt"
import "core:os"
import filepath "core:path/filepath"
import "core:strings"

dump_tree :: proc(app: ^App) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintfln(&builder, "e3 tree dump")
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

	temp_dir, temp_err := os.temp_dir(context.temp_allocator)
	if temp_err != nil {
		return false
	}
	path, path_err := filepath.join({temp_dir, "e3-tree.log"}, context.temp_allocator)
	if path_err != nil {
		return false
	}
	return os.write_entire_file(path, strings.to_string(builder)) == nil
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
			" %s pane_id=%d bounds=(%d,%d %dx%d) split_active=%v split_kind=%v fullscreen=%v title=%s",
			focused_marker,
			pane.id,
			pane.bounds.x,
			pane.bounds.y,
			pane.bounds.width,
			pane.bounds.height,
			pane.split_active,
			pane.split_kind,
			pane.fullscreen,
			pane_title(pane),
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
