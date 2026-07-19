package terminal

import "core:c"

foreign import ghostty "system:ghostty-vt"

GhosttyResult :: enum c.int {
	SUCCESS        = 0,
	OUT_OF_MEMORY  = -1,
	INVALID_VALUE  = -2,
	OUT_OF_SPACE   = -3,
	NO_VALUE       = -4,
}

GhosttyTerminal :: distinct rawptr
GhosttyRenderState :: distinct rawptr
GhosttyRenderStateRowIterator :: distinct rawptr
GhosttyRenderStateRowCells :: distinct rawptr

GhosttyTerminalOptions :: struct {
	cols:           u16,
	rows:           u16,
	max_scrollback: c.size_t,
}

GhosttyColorRgb :: struct {
	r: u8,
	g: u8,
	b: u8,
}

GhosttyTerminalOption :: enum c.int {
	USERDATA          = 0,
	WRITE_PTY         = 1,
	COLOR_FOREGROUND  = 11,
	COLOR_BACKGROUND  = 12,
	COLOR_CURSOR      = 13,
	COLOR_PALETTE     = 14,
}

GhosttyTerminalData :: enum c.int {
	INVALID                    = 0,
	TITLE                 = 12,
	COLOR_PALETTE         = 21,
	COLOR_PALETTE_DEFAULT = 25,
}

// Borrowed byte string; valid until the next ghostty_terminal_vt_write/reset.
GhosttyString :: struct {
	ptr: [^]u8,
	len: c.size_t,
}

GhosttyTerminalWritePtyFn :: proc "c" (terminal: GhosttyTerminal, userdata: rawptr, data: [^]u8, len: c.size_t)

GhosttyTerminalScrollViewportTag :: enum c.int {
	TOP    = 0,
	BOTTOM = 1,
	DELTA  = 2,
}

GhosttyTerminalScrollViewportValue :: struct #raw_union {
	delta:   c.ptrdiff_t,
	padding: [2]u64,
}

GhosttyTerminalScrollViewport :: struct {
	tag:   GhosttyTerminalScrollViewportTag,
	value: GhosttyTerminalScrollViewportValue,
}

GhosttyRenderStateData :: enum c.int {
	INVALID                    = 0,
	COLS                       = 1,
	ROWS                       = 2,
	DIRTY                      = 3,
	ROW_ITERATOR               = 4,
	CURSOR_VIEWPORT_HAS_VALUE  = 14,
	CURSOR_VIEWPORT_X          = 15,
	CURSOR_VIEWPORT_Y          = 16,
}

GhosttyRenderStateRowData :: enum c.int {
	INVALID = 0,
	DIRTY   = 1,
	RAW     = 2,
	CELLS   = 3,
}

GhosttyRenderStateRowCellsData :: enum c.int {
	INVALID       = 0,
	RAW           = 1,
	STYLE         = 2,
	GRAPHEMES_LEN = 3,
	GRAPHEMES_BUF = 4,
	BG_COLOR      = 5,
	FG_COLOR      = 6,
}

GhosttyStyleColorTag :: enum c.int {
	NONE    = 0,
	PALETTE = 1,
	RGB     = 2,
}

GhosttyStyleColorValue :: struct #raw_union {
	palette: u8,
	rgb:     GhosttyColorRgb,
	padding: u64,
}

GhosttyStyleColor :: struct {
	tag:   GhosttyStyleColorTag,
	value: GhosttyStyleColorValue,
}

GhosttyStyle :: struct {
	size:            c.size_t,
	fg_color:        GhosttyStyleColor,
	bg_color:        GhosttyStyleColor,
	underline_color: GhosttyStyleColor,
	bold:            bool,
	italic:          bool,
	faint:           bool,
	blink:           bool,
	inverse:         bool,
	invisible:       bool,
	strikethrough:   bool,
	overline:        bool,
	underline:       c.int,
}

@(default_calling_convention = "c")
foreign ghostty {
	ghostty_terminal_new :: proc(allocator: rawptr, terminal: ^GhosttyTerminal, options: GhosttyTerminalOptions) -> GhosttyResult ---
	ghostty_terminal_free :: proc(terminal: GhosttyTerminal) ---
	ghostty_terminal_resize :: proc(terminal: GhosttyTerminal, cols: u16, rows: u16, cell_width_px: u32, cell_height_px: u32) -> GhosttyResult ---
	ghostty_terminal_set :: proc(terminal: GhosttyTerminal, option: GhosttyTerminalOption, value: rawptr) -> GhosttyResult ---
	ghostty_terminal_get :: proc(terminal: GhosttyTerminal, data: GhosttyTerminalData, out: rawptr) -> GhosttyResult ---
	ghostty_terminal_vt_write :: proc(terminal: GhosttyTerminal, data: [^]u8, len: c.size_t) ---
	ghostty_terminal_scroll_viewport :: proc(terminal: GhosttyTerminal, behavior: GhosttyTerminalScrollViewport) ---

	ghostty_render_state_new :: proc(allocator: rawptr, state: ^GhosttyRenderState) -> GhosttyResult ---
	ghostty_render_state_free :: proc(state: GhosttyRenderState) ---
	ghostty_render_state_update :: proc(state: GhosttyRenderState, terminal: GhosttyTerminal) -> GhosttyResult ---
	ghostty_render_state_get :: proc(state: GhosttyRenderState, data: GhosttyRenderStateData, out: rawptr) -> GhosttyResult ---

	ghostty_render_state_row_iterator_new :: proc(allocator: rawptr, iterator: ^GhosttyRenderStateRowIterator) -> GhosttyResult ---
	ghostty_render_state_row_iterator_free :: proc(iterator: GhosttyRenderStateRowIterator) ---
	ghostty_render_state_row_iterator_next :: proc(iterator: GhosttyRenderStateRowIterator) -> bool ---

	ghostty_render_state_row_get :: proc(iterator: GhosttyRenderStateRowIterator, data: GhosttyRenderStateRowData, out: rawptr) -> GhosttyResult ---

	ghostty_render_state_row_cells_new :: proc(allocator: rawptr, cells: ^GhosttyRenderStateRowCells) -> GhosttyResult ---
	ghostty_render_state_row_cells_free :: proc(cells: GhosttyRenderStateRowCells) ---
	ghostty_render_state_row_cells_next :: proc(cells: GhosttyRenderStateRowCells) -> bool ---
	ghostty_render_state_row_cells_get :: proc(cells: GhosttyRenderStateRowCells, data: GhosttyRenderStateRowCellsData, out: rawptr) -> GhosttyResult ---
}

ghostty_succeeded :: proc(result: GhosttyResult) -> bool {
	return result == .SUCCESS
}
