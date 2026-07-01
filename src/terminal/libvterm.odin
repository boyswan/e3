package terminal

import "core:c"

foreign import libvterm "system:vterm"

VTERM_MAX_CHARS_PER_CELL :: 6

VTerm :: struct {}
VTermState :: struct {}
VTermScreen :: struct {}

VTermPos :: struct {
	row: c.int,
	col: c.int,
}

VTermRect :: struct {
	start_row: c.int,
	end_row:   c.int,
	start_col: c.int,
	end_col:   c.int,
}

VTermColor_Type :: enum u8 {
	RGB        = 0x00,
	Indexed    = 0x01,
	Default_FG = 0x02,
	Default_BG = 0x04,
}

VTermColor :: struct {
	type: u8,
	red:  u8,
	green: u8,
	blue: u8,
}

VTermScreenCellAttrs :: distinct u32

VTERM_ATTR_BOLD_MASK       :: VTermScreenCellAttrs(1 << 0)
VTERM_ATTR_UNDERLINE_MASK  :: VTermScreenCellAttrs(0b11 << 1)
VTERM_ATTR_ITALIC_MASK     :: VTermScreenCellAttrs(1 << 3)
VTERM_ATTR_BLINK_MASK      :: VTermScreenCellAttrs(1 << 4)
VTERM_ATTR_REVERSE_MASK    :: VTermScreenCellAttrs(1 << 5)
VTERM_ATTR_CONCEAL_MASK    :: VTermScreenCellAttrs(1 << 6)
VTERM_ATTR_STRIKE_MASK     :: VTermScreenCellAttrs(1 << 7)
VTERM_ATTR_FONT_MASK       :: VTermScreenCellAttrs(0b1111 << 8)
VTERM_ATTR_DWL_MASK        :: VTermScreenCellAttrs(1 << 12)
VTERM_ATTR_DHL_MASK        :: VTermScreenCellAttrs(0b11 << 13)
VTERM_ATTR_SMALL_MASK      :: VTermScreenCellAttrs(1 << 15)
VTERM_ATTR_BASELINE_MASK   :: VTermScreenCellAttrs(0b11 << 16)

VTermScreenCell :: struct {
	chars: [VTERM_MAX_CHARS_PER_CELL]u32,
	width: c.char,
	attrs: VTermScreenCellAttrs,
	fg:    VTermColor,
	bg:    VTermColor,
}

VTermDamageSize :: enum c.int {
	Cell,
	Row,
	Screen,
	Scroll,
}

@(default_calling_convention = "c", link_prefix = "vterm_")
foreign libvterm {
	check_version :: proc(major: c.int, minor: c.int) ---

	new  :: proc(rows: c.int, cols: c.int) -> ^VTerm ---
	free :: proc(vt: ^VTerm) ---

	get_size :: proc(vt: ^VTerm, rows: ^c.int, cols: ^c.int) ---
	set_size :: proc(vt: ^VTerm, rows: c.int, cols: c.int) ---

	get_utf8 :: proc(vt: ^VTerm) -> c.int ---
	set_utf8 :: proc(vt: ^VTerm, is_utf8: c.int) ---

	input_write :: proc(vt: ^VTerm, bytes: [^]u8, len: c.size_t) -> c.size_t ---

	output_get_buffer_current :: proc(vt: ^VTerm) -> c.size_t ---
	output_read :: proc(vt: ^VTerm, buffer: [^]u8, len: c.size_t) -> c.size_t ---

	obtain_state :: proc(vt: ^VTerm) -> ^VTermState ---
	obtain_screen :: proc(vt: ^VTerm) -> ^VTermScreen ---
}

@(default_calling_convention = "c", link_prefix = "vterm_state_")
foreign libvterm {
	get_cursorpos :: proc(state: ^VTermState, cursorpos: ^VTermPos) ---
}

@(default_calling_convention = "c", link_prefix = "vterm_screen_")
foreign libvterm {
	flush_damage :: proc(screen: ^VTermScreen) ---
	set_damage_merge :: proc(screen: ^VTermScreen, size: VTermDamageSize) ---
	reset :: proc(screen: ^VTermScreen, hard: c.int) ---
	get_cell :: proc(screen: ^VTermScreen, pos: VTermPos, cell: ^VTermScreenCell) -> c.int ---
	convert_color_to_rgb :: proc(screen: ^VTermScreen, color: ^VTermColor) ---
	set_default_colors :: proc(screen: ^VTermScreen, default_fg: ^VTermColor, default_bg: ^VTermColor) ---
}

color_is_indexed :: proc(color: ^VTermColor) -> bool {
	return color.type & u8(VTermColor_Type.Indexed) == u8(VTermColor_Type.Indexed)
}

color_is_rgb :: proc(color: ^VTermColor) -> bool {
	return color.type & u8(VTermColor_Type.Indexed) == 0
}

color_is_default_fg :: proc(color: ^VTermColor) -> bool {
	return color.type & u8(VTermColor_Type.Default_FG) != 0
}

color_is_default_bg :: proc(color: ^VTermColor) -> bool {
	return color.type & u8(VTermColor_Type.Default_BG) != 0
}

cell_is_bold :: proc(cell: ^VTermScreenCell) -> bool {
	return cell.attrs & VTERM_ATTR_BOLD_MASK != 0
}

cell_is_reverse :: proc(cell: ^VTermScreenCell) -> bool {
	return cell.attrs & VTERM_ATTR_REVERSE_MASK != 0
}
