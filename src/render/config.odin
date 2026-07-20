package render

RGB_Color :: struct {
	r: u8,
	g: u8,
	b: u8,
}

Workspace_Button_Colors :: struct {
	border: RGB_Color,
	background: RGB_Color,
	text: RGB_Color,
}

Bar_Colors :: struct {
	background: RGB_Color,
	statusline: RGB_Color,
	separator: RGB_Color,
	focused_workspace: Workspace_Button_Colors,
	active_workspace: Workspace_Button_Colors,
	inactive_workspace: Workspace_Button_Colors,
	urgent_workspace: Workspace_Button_Colors,
	binding_mode: Workspace_Button_Colors,
}

Client_Color :: struct {
	border:       RGB_Color,
	background:   RGB_Color,
	text:         RGB_Color,
	indicator:    RGB_Color,
	child_border: RGB_Color,
}

Client_Colors :: struct {
	focused:          Client_Color,
	focused_inactive: Client_Color,
	unfocused:        Client_Color,
	urgent:           Client_Color,
	focused_tab_title: Client_Color,
	background:       RGB_Color,
}

Renderer_Config :: struct {
	font_path:   string,
	font_family: string,
	font_size:   f32,
	native_pane_padding_px: int,
	native_pane_border_px:  int,

	background_set: bool,
	background_r:   u8,
	background_g:   u8,
	background_b:   u8,
	foreground_set: bool,
	foreground_r:   u8,
	foreground_g:   u8,
	foreground_b:   u8,
	palette:        [16]RGB_Color,
	bar:            Bar_Colors,
	client:         Client_Colors,
}

renderer_default_config :: proc() -> Renderer_Config {
	config := Renderer_Config {
		// Generic monospace resolves to the user's system fixed-pitch font on
		// macOS and Fontconfig's default monospace family elsewhere.
		font_family = "monospace",
		font_size = 14,
		native_pane_padding_px = 10,
		native_pane_border_px = 1,
		background_set = true,
		background_r = 0x23,
		background_g = 0x23,
		background_b = 0x26,
		foreground_set = true,
		foreground_r = 0xe1,
		foreground_g = 0xe1,
		foreground_b = 0xe1,
	}

	config.palette[0] = RGB_Color{0x18, 0x1a, 0x1f}
	config.palette[1] = RGB_Color{0xe8, 0x66, 0x71}
	config.palette[2] = RGB_Color{0x98, 0xc3, 0x79}
	config.palette[3] = RGB_Color{0xe5, 0xc0, 0x7b}
	config.palette[4] = RGB_Color{0x61, 0xaf, 0xef}
	config.palette[5] = RGB_Color{0xc6, 0x78, 0xdd}
	config.palette[6] = RGB_Color{0x56, 0xb6, 0xc2}
	config.palette[7] = RGB_Color{0xab, 0xb2, 0xbf}
	config.palette[8] = RGB_Color{0x5c, 0x63, 0x70}
	config.palette[9] = RGB_Color{0xe8, 0x66, 0x71}
	config.palette[10] = RGB_Color{0x98, 0xc3, 0x79}
	config.palette[11] = RGB_Color{0xe5, 0xc0, 0x7b}
	config.palette[12] = RGB_Color{0x61, 0xaf, 0xef}
	config.palette[13] = RGB_Color{0xc6, 0x78, 0xdd}
	config.palette[14] = RGB_Color{0x56, 0xb6, 0xc2}
	config.palette[15] = RGB_Color{0xab, 0xb2, 0xbf}

	config.bar.background = RGB_Color{0x00, 0x00, 0x00}
	config.bar.statusline = RGB_Color{0xff, 0xff, 0xff}
	config.bar.separator = RGB_Color{0x66, 0x66, 0x66}
	config.bar.focused_workspace = Workspace_Button_Colors{border = RGB_Color{0x4c, 0x78, 0x99}, background = RGB_Color{0x28, 0x55, 0x77}, text = RGB_Color{0xff, 0xff, 0xff}}
	config.bar.active_workspace = Workspace_Button_Colors{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x5f, 0x67, 0x6a}, text = RGB_Color{0xff, 0xff, 0xff}}
	config.bar.inactive_workspace = Workspace_Button_Colors{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x22, 0x22, 0x22}, text = RGB_Color{0x88, 0x88, 0x88}}
	config.bar.urgent_workspace = Workspace_Button_Colors{border = RGB_Color{0x2f, 0x34, 0x3a}, background = RGB_Color{0x90, 0x00, 0x00}, text = RGB_Color{0xff, 0xff, 0xff}}
	config.bar.binding_mode = Workspace_Button_Colors{border = RGB_Color{0x2f, 0x34, 0x3a}, background = RGB_Color{0x90, 0x00, 0x00}, text = RGB_Color{0xff, 0xff, 0xff}}

	config.client.focused = Client_Color{border = RGB_Color{0x4c, 0x78, 0x99}, background = RGB_Color{0x28, 0x55, 0x77}, text = RGB_Color{0xff, 0xff, 0xff}, indicator = RGB_Color{0x2e, 0x9e, 0xf4}, child_border = RGB_Color{0x28, 0x55, 0x77}}
	config.client.focused_inactive = Client_Color{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x5f, 0x67, 0x6a}, text = RGB_Color{0xff, 0xff, 0xff}, indicator = RGB_Color{0x48, 0x4e, 0x50}, child_border = RGB_Color{0x5f, 0x67, 0x6a}}
	config.client.unfocused = Client_Color{border = RGB_Color{0x33, 0x33, 0x33}, background = RGB_Color{0x22, 0x22, 0x22}, text = RGB_Color{0x88, 0x88, 0x88}, indicator = RGB_Color{0x29, 0x2d, 0x2e}, child_border = RGB_Color{0x22, 0x22, 0x22}}
	config.client.urgent = Client_Color{border = RGB_Color{0x2f, 0x34, 0x3a}, background = RGB_Color{0x90, 0x00, 0x00}, text = RGB_Color{0xff, 0xff, 0xff}, indicator = RGB_Color{0x90, 0x00, 0x00}, child_border = RGB_Color{0x90, 0x00, 0x00}}
	config.client.focused_tab_title = config.client.focused_inactive
	config.client.background = RGB_Color{0xff, 0xff, 0xff}

	return config
}

renderer_config_background :: proc(config: Renderer_Config) -> (u8, u8, u8) {
	if config.background_set {
		return config.background_r, config.background_g, config.background_b
	}
	return 0x23, 0x23, 0x26
}

renderer_config_foreground :: proc(config: Renderer_Config) -> (u8, u8, u8) {
	if config.foreground_set {
		return config.foreground_r, config.foreground_g, config.foreground_b
	}
	return 0xe1, 0xe1, 0xe1
}
