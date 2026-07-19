package render

import "core:unicode/utf8"

import domain "../app"
import input "../input"

render_app :: proc(buffer: ^Screen_Buffer, state: ^domain.App, bounds: domain.Rect, mode := input.Input_Mode.Normal, native_chrome := false, terminal_width_padding := 0, terminal_height_padding := 0) {
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
	terminal_inset := 1
	if native_chrome {
		terminal_inset = 0
	}
	domain.sync_pane_terminals(workspace.root, terminal_inset, terminal_width_padding, terminal_height_padding)
	if !native_chrome {
		render_split_separators(buffer, workspace.root)
		screen_draw_box(buffer, content_bounds)
		render_pane_borders(buffer, workspace.root, workspace.focused_pane_id, content_bounds)
		render_focused_pane_border(buffer, state, workspace, content_bounds, mode)
	}
	render_tab_bars(buffer, workspace.root)
	render_pane_labels(buffer, workspace.root, workspace.focused_pane_id, native_chrome)
	render_workspace_bar(buffer, state, mode, domain.Rect{x = bounds.x, y = bounds.y + bounds.height - 1, width = bounds.width, height = 1}, native_chrome)
}

render_workspace_bar :: proc(buffer: ^Screen_Buffer, state: ^domain.App, mode: input.Input_Mode, bounds: domain.Rect, native_chrome := false) {
	_ = native_chrome
	cursor_x := bounds.x
	bar_bg := buffer.bar.background
	screen_set_range_background(buffer, bounds.x, bounds.y, bounds.width, bar_bg.r, bar_bg.g, bar_bg.b)

	// i3bar draws the binding mode indicator before the workspace buttons.
	if mode == .Resize {
		cursor_x = render_workspace_button(buffer, cursor_x, bounds.y, "resize", buffer.bar.binding_mode, true)
	}

	for index in 0 ..< len(state.workspaces) {
		workspace := &state.workspaces[index]
		active := index == state.active_workspace_index
		colors := buffer.bar.inactive_workspace
		if active {
			colors = buffer.bar.focused_workspace
		}

		cursor_x = render_workspace_button(buffer, cursor_x, bounds.y, workspace.name, colors, active)
	}

	_ = cursor_x
}

render_workspace_button :: proc(buffer: ^Screen_Buffer, x: int, y: int, name: string, colors: Workspace_Button_Colors, bold := false) -> int {
	cursor_x := x
	screen_put_rgb(buffer, cursor_x, y, " ", colors.text, colors.background, bold)
	cursor_x += 1
	for offset in 0 ..< len(name) {
		screen_put_rgb(buffer, cursor_x, y, name[offset:offset + 1], colors.text, colors.background, bold)
		cursor_x += 1
	}
	screen_put_rgb(buffer, cursor_x, y, " ", colors.text, colors.background, bold)
	cursor_x += 1
	return cursor_x
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

render_tab_bars :: proc(buffer: ^Screen_Buffer, node: ^domain.Node) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		return
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			render_tab_bars(buffer, child)
		}
	case .Stacked:
		render_stack_bar(buffer, node)
		child := domain.focused_child(node)
		if child != nil {
			render_tab_bars(buffer, child)
		}
	case .Tabbed:
		render_tab_bar(buffer, node)
		child := domain.focused_child(node)
		if child != nil {
			render_tab_bars(buffer, child)
		}
	}
}

render_stack_bar :: proc(buffer: ^Screen_Buffer, node: ^domain.Node) {
	child_count := len(node.children)
	if child_count == 0 {
		return
	}

	focused := domain.focused_child(node)
	focused_colors := Workspace_Button_Colors{border = RGB_Color{0x4c, 0x78, 0x99}, background = RGB_Color{0x28, 0x55, 0x77}, text = RGB_Color{0xff, 0xff, 0xff}}
	inactive_colors := Workspace_Button_Colors{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x22, 0x22, 0x22}, text = RGB_Color{0x88, 0x88, 0x88}}

	for child in node.children {
		deco := child.deco_bounds
		if deco.width <= 0 || deco.height <= 0 {
			continue
		}

		colors := inactive_colors
		if child == focused {
			colors = focused_colors
		}
		render_tab_button(buffer, child, deco.x, deco.y, deco.width, colors)
	}
}

render_tab_bar :: proc(buffer: ^Screen_Buffer, node: ^domain.Node) {
	child_count := len(node.children)
	if child_count == 0 {
		return
	}

	focused := domain.focused_child(node)
	focused_colors := Workspace_Button_Colors{border = RGB_Color{0x4c, 0x78, 0x99}, background = RGB_Color{0x28, 0x55, 0x77}, text = RGB_Color{0xff, 0xff, 0xff}}
	inactive_colors := Workspace_Button_Colors{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x22, 0x22, 0x22}, text = RGB_Color{0x88, 0x88, 0x88}}

	for index in 0 ..< child_count {
		child := node.children[index]
		deco := child.deco_bounds
		if deco.width <= 0 || deco.height <= 0 {
			continue
		}

		colors := inactive_colors
		if child == focused {
			colors = focused_colors
		}
		render_tab_button(buffer, child, deco.x, deco.y, deco.width, colors)
	}
}

render_tab_button :: proc(buffer: ^Screen_Buffer, child: ^domain.Node, x: int, y: int, width: int, colors: Workspace_Button_Colors) {
	if width <= 0 {
		return
	}

	for offset in 0 ..< width {
		screen_put_rgb(buffer, x + offset, y, " ", colors.text, colors.background)
	}

	title_width := node_title_width(child)
	if title_width <= 0 {
		return
	}
	start_x := x + max_int((width - title_width) / 2, 0)
	render_node_title(buffer, child, start_x, y, colors.text, colors.background, x + width)
}

node_title_width :: proc(node: ^domain.Node) -> int {
	if node == nil {
		return 0
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil {
			return 0
		}
		// Use the pane's cached client title or native cwd/process fallback.
		if title := domain.pane_title(node.pane); len(title) > 0 {
			return title_cell_width(title)
		}
		return digit_count(node.pane.id)
	case .Split_Horizontal, .Split_Vertical, .Stacked, .Tabbed:
		width := 3
		for index in 0 ..< len(node.children) {
			if index > 0 {
				width += 1
			}
			width += node_title_width(node.children[index])
		}
		return width
	}

	return 0
}

render_node_title :: proc(buffer: ^Screen_Buffer, node: ^domain.Node, x: int, y: int, fg: RGB_Color, bg: RGB_Color, max_x: int) -> int {
	if node == nil {
		return x
	}

	cursor_x := x
	switch node.kind {
	case .Pane:
		if node.pane != nil {
			title := domain.pane_title(node.pane)
			if len(title) > 0 {
				cursor_x = render_title_text(buffer, cursor_x, y, title, fg, bg, max_x)
			} else {
				cursor_x = render_put_int_rgb(buffer, cursor_x, y, node.pane.id, fg, bg)
			}
		}
	case .Split_Horizontal, .Split_Vertical, .Stacked, .Tabbed:
		cursor_x = put_title_cell(buffer, cursor_x, y, node_title_layout_glyph(node.kind), fg, bg, max_x)
		cursor_x = put_title_cell(buffer, cursor_x, y, "[", fg, bg, max_x)
		for index in 0 ..< len(node.children) {
			if index > 0 {
				cursor_x = put_title_cell(buffer, cursor_x, y, " ", fg, bg, max_x)
			}
			cursor_x = render_node_title(buffer, node.children[index], cursor_x, y, fg, bg, max_x)
		}
		cursor_x = put_title_cell(buffer, cursor_x, y, "]", fg, bg, max_x)
	}

	return cursor_x
}

// Clips glyphs at max_x while still advancing the cursor so centering math
// and recursion stay consistent.
put_title_cell :: proc(buffer: ^Screen_Buffer, x: int, y: int, glyph: string, fg: RGB_Color, bg: RGB_Color, max_x: int) -> int {
	if x < max_x {
		screen_put_rgb(buffer, x, y, glyph, fg, bg)
	}
	return x + 1
}

title_cell_width :: proc(title: string) -> int {
	width := 0
	remaining := title
	for len(remaining) > 0 {
		r, size := utf8.decode_rune_in_string(remaining)
		remaining = remaining[size:]
		if r < 0x20 || r == 0x7f {
			continue
		}
		width += 1
	}
	return width
}

render_title_text :: proc(buffer: ^Screen_Buffer, x: int, y: int, title: string, fg: RGB_Color, bg: RGB_Color, max_x: int) -> int {
	cursor_x := x
	remaining := title
	for len(remaining) > 0 && cursor_x < max_x {
		r, size := utf8.decode_rune_in_string(remaining)
		remaining = remaining[size:]
		if r < 0x20 || r == 0x7f {
			continue
		}
		screen_put_rune_rgb(buffer, cursor_x, y, u32(r), fg, bg)
		cursor_x += 1
	}
	return cursor_x
}

node_title_layout_glyph :: proc(kind: domain.Node_Kind) -> string {
	switch kind {
	case .Split_Horizontal:
		return "H"
	case .Split_Vertical:
		return "V"
	case .Stacked:
		return "S"
	case .Tabbed:
		return "T"
	case .Pane:
		return ""
	}
	return ""
}

render_put_int_rgb :: proc(buffer: ^Screen_Buffer, x: int, y: int, value: int, fg: RGB_Color, bg: RGB_Color) -> int {
	cursor_x := x
	remaining := value
	if remaining == 0 {
		screen_put_rgb(buffer, cursor_x, y, "0", fg, bg)
		return cursor_x + 1
	}

	digits: [20]int
	count := 0
	for remaining > 0 && count < len(digits) {
		digits[count] = remaining % 10
		remaining /= 10
		count += 1
	}

	for count > 0 {
		count -= 1
		screen_put_rgb(buffer, cursor_x, y, digit_string(digits[count]), fg, bg)
		cursor_x += 1
	}
	return cursor_x
}

digit_count :: proc(value: int) -> int {
	if value == 0 {
		return 1
	}
	count := 0
	remaining := value
	for remaining > 0 {
		remaining /= 10
		count += 1
	}
	return count
}

render_pane_labels :: proc(buffer: ^Screen_Buffer, node: ^domain.Node, focused_pane_id: int, native_chrome := false) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane != nil {
			render_pane_label(buffer, node.pane, node.pane.id == focused_pane_id, native_chrome)
		}
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			render_pane_labels(buffer, child, focused_pane_id, native_chrome)
		}
	case .Stacked, .Tabbed:
		child := domain.focused_child(node)
		if child != nil {
			render_pane_labels(buffer, child, focused_pane_id, native_chrome)
		}
	}
}

render_pane_label :: proc(buffer: ^Screen_Buffer, pane: ^domain.Pane, focused: bool, native_chrome := false) {
	bounds := pane.bounds
	if bounds.width <= 0 || bounds.height <= 0 {
		return
	}

	inset := 1
	if native_chrome {
		inset = 0
	}
	render_terminal_contents(buffer, pane, focused, inset)
}

render_pane_borders :: proc(buffer: ^Screen_Buffer, node: ^domain.Node, focused_pane_id: int, content_bounds: domain.Rect) {
	if node == nil {
		return
	}

	switch node.kind {
	case .Pane:
		if node.pane == nil || node.pane.id == focused_pane_id {
			return
		}

		color := Cell_Color.Inactive
		if node.parent != nil && len(node.parent.focus_order) > 0 && node.parent.focus_order[0] == node {
			color = .Focused_Inactive
		}
		render_pane_border(buffer, node.pane.bounds, content_bounds, color)
	case .Split_Horizontal, .Split_Vertical:
		for child in node.children {
			render_pane_borders(buffer, child, focused_pane_id, content_bounds)
		}
	case .Stacked, .Tabbed:
		child := domain.focused_child(node)
		if child != nil {
			render_pane_borders(buffer, child, focused_pane_id, content_bounds)
		}
	}
}

render_pane_border :: proc(buffer: ^Screen_Buffer, bounds: domain.Rect, content_bounds: domain.Rect, color: Cell_Color) {
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
		screen_set_color(buffer, x, top, color)
		screen_set_color(buffer, x, bottom, color)
	}

	for y in top ..= bottom {
		screen_set_color(buffer, left, y, color)
		screen_set_color(buffer, right, y, color)
	}
}

render_focused_pane_border :: proc(buffer: ^Screen_Buffer, state: ^domain.App, workspace: ^domain.Workspace, content_bounds: domain.Rect, mode: input.Input_Mode) {
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

	border_color := Cell_Color.Focused
	if mode == .Resize {
		border_color = .Split_Hint
	}

	for x in left ..= right {
		screen_set_color(buffer, x, top, border_color)
		screen_set_color(buffer, x, bottom, border_color)
	}

	for y in top ..= bottom {
		screen_set_color(buffer, left, y, border_color)
		screen_set_color(buffer, right, y, border_color)
	}

	if mode == .Resize {
		return
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
		if node.bounds.width > 0 && node.bounds.height > 0 {
			return node.bounds, true
		}
		child := domain.focused_child(node)
		if child != nil {
			return node_bounds(child)
		}
		return domain.Rect{}, false
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
