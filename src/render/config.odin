package render

Renderer_Config :: struct {
	font_path:   string,
	font_family: string,
	font_size:   f32,

	background_set: bool,
	background_r:   u8,
	background_g:   u8,
	background_b:   u8,
}

renderer_default_config :: proc() -> Renderer_Config {
	return Renderer_Config {
		font_family = "monospace",
		font_size = 18,
		background_set = true,
		background_r = 10,
		background_g = 10,
		background_b = 12,
	}
}

renderer_config_background :: proc(config: Renderer_Config) -> (u8, u8, u8) {
	if config.background_set {
		return config.background_r, config.background_g, config.background_b
	}
	return 10, 10, 12
}
