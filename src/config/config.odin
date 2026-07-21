package config

import "core:fmt"
import "core:os"
import "core:strings"
import posix "core:sys/posix"
import input "../input"
import render "../render"

Config :: struct {
	renderer:      render.Renderer_Config,
	mod_key:       input.Mod_Key,
	bindings:      input.Key_Bindings,
	shell_command: string,
}

load_config :: proc(config_path := "") -> Config {
	default_mod_key := input.Mod_Key.Alt
	when ODIN_OS == .Darwin {
		default_mod_key = .Super
	}

	config := Config {
		renderer = render.renderer_default_config(),
		mod_key = default_mod_key,
		bindings = input.key_bindings_default(),
	}
	path := find_config_path(config_path)
	if path == "" {
		return config
	}

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil || len(data) == 0 {
		return config
	}

	parse_config(string(data), &config)
	return config
}

load_renderer_config :: proc() -> render.Renderer_Config {
	return load_config().renderer
}

find_config_path :: proc(config_path := "") -> string {
	if config_path != "" {
		return config_path
	}

	// Configuration is user-scoped. Never inspect the process working
	// directory: launching e3 from a source checkout must behave exactly like
	// launching it from any other directory.
	explicit_path := os.get_env("E3_CONFIG", context.temp_allocator)
	if explicit_path != "" && os.exists(explicit_path) {
		return explicit_path
	}

	xdg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
	if xdg != "" {
		path := fmt.aprintf("%s/e3/config.yaml", xdg, allocator = context.temp_allocator)
		if os.exists(path) {
			return path
		}

		legacy_path := fmt.aprintf("%s/odin-play/config.yaml", xdg, allocator = context.temp_allocator)
		if os.exists(legacy_path) {
			return legacy_path
		}
	}

	home := os.get_env("HOME", context.temp_allocator)
	if path := find_config_in_home(home); path != "" {
		return path
	}

	// GUI launchers do not consistently provide a shell-style HOME
	// environment. Also try the account database, which is authoritative for
	// the current macOS/Linux user and works when HOME is absent or incorrect.
	account_home := account_home_directory()
	if account_home != home {
		if path := find_config_in_home(account_home); path != "" {
			return path
		}
	}

	return ""
}

account_home_directory :: proc() -> string {
	account := posix.getpwuid(posix.getuid())
	if account == nil || account.pw_dir == nil {
		return ""
	}
	return strings.clone(string(account.pw_dir), context.temp_allocator)
}

find_config_in_home :: proc(home: string) -> string {
	if home == "" {
		return ""
	}

	path := fmt.aprintf("%s/.config/e3/config.yaml", home, allocator = context.temp_allocator)
	if os.exists(path) {
		return path
	}

	when ODIN_OS == .Darwin {
		macos_path := fmt.aprintf("%s/Library/Application Support/e3/config.yaml", home, allocator = context.temp_allocator)
		if os.exists(macos_path) {
			return macos_path
		}
	}

	legacy_path := fmt.aprintf("%s/.config/odin-play/config.yaml", home, allocator = context.temp_allocator)
	if os.exists(legacy_path) {
		return legacy_path
	}
	return ""
}

parse_config :: proc(data: string, config: ^Config) {
	section := ""
	start := 0
	for start <= len(data) {
		end := start
		for end < len(data) && data[end] != '\n' {
			end += 1
		}

		line := strings.trim_space(data[start:end])
		parse_config_line(line, &section, config)

		if end >= len(data) {
			break
		}
		start = end + 1
	}
}

parse_config_line :: proc(line: string, section: ^string, config: ^Config) {
	if line == "" || line[0] == '#' {
		return
	}

	if line[len(line) - 1] == ':' {
		section^ = strings.trim_space(line[:len(line) - 1])
		return
	}

	colon := find_char(line, ':')
	if colon < 0 {
		return
	}

	key := strings.trim_space(line[:colon])
	value := clean_value(strings.trim_space(line[colon + 1:]))
	apply_config_value(section^, key, value, config)
}

apply_config_value :: proc(section: string, key: string, value: string, config: ^Config) {
	if section == "font" {
		switch key {
		case "path":
			config.renderer.font_path = value
		case "family":
			config.renderer.font_family = value
		case "size":
			if size, ok := parse_int(value); ok && size > 0 {
				config.renderer.font_size = f32(size)
			}
		}
		return
	}

	if section == "window" || section == "renderer" {
		apply_window_value(key, value, &config.renderer)
		return
	}

	if section == "pane" || section == "panes" {
		apply_pane_value(key, value, &config.renderer)
		return
	}

	if section == "bar" || section == "workspace_bar" {
		apply_bar_value(key, value, &config.renderer)
		return
	}

	if section == "client" || section == "client_colors" {
		apply_client_value(key, value, &config.renderer)
		return
	}

	if section == "input" || section == "keys" {
		apply_input_value(key, value, config)
		return
	}

	if section == "shell" {
		if key == "command" || key == "path" {
			config.shell_command = value
		}
		return
	}

	if section == "palette" || section == "colors" || section == "colours" {
		apply_palette_value(key, value, &config.renderer)
		return
	}

	switch key {
	case "font_path":
		config.renderer.font_path = value
	case "font_family":
		config.renderer.font_family = value
	case "font_size":
		if size, ok := parse_int(value); ok && size > 0 {
			config.renderer.font_size = f32(size)
		}
	case "background", "background_color":
		apply_background_value(value, &config.renderer)
	case "foreground", "foreground_color":
		apply_foreground_value(value, &config.renderer)
	case "mod", "mod_key":
		config.mod_key = parse_mod_key(value, config.mod_key)
	case "shell", "shell_command":
		config.shell_command = value
	}
}

apply_window_value :: proc(key: string, value: string, config: ^render.Renderer_Config) {
	switch key {
	case "background", "background_color":
		apply_background_value(value, config)
	case "foreground", "foreground_color":
		apply_foreground_value(value, config)
	}
}

apply_pane_value :: proc(key: string, value: string, config: ^render.Renderer_Config) {
	switch key {
	case "native_padding", "native_padding_px", "native_pane_padding", "native_pane_padding_px":
		if padding, ok := parse_int(value); ok && padding >= 0 {
			config.native_pane_padding_px = padding
		}
	case "native_border", "native_border_px", "native_pane_border", "native_pane_border_px":
		if border, ok := parse_int(value); ok && border >= 0 {
			config.native_pane_border_px = border
		}
	}
}

apply_bar_value :: proc(key: string, value: string, config: ^render.Renderer_Config) {
	switch key {
	case "background":
		if r, g, b, ok := parse_hex_color(value); ok {
			config.bar.background = render.RGB_Color{r, g, b}
		}
	case "statusline":
		if r, g, b, ok := parse_hex_color(value); ok {
			config.bar.statusline = render.RGB_Color{r, g, b}
		}
	case "separator":
		if r, g, b, ok := parse_hex_color(value); ok {
			config.bar.separator = render.RGB_Color{r, g, b}
		}
	case "focused_workspace":
		if colors, ok := parse_workspace_button_colors(value); ok {
			config.bar.focused_workspace = colors
		}
	case "active_workspace":
		if colors, ok := parse_workspace_button_colors(value); ok {
			config.bar.active_workspace = colors
		}
	case "inactive_workspace":
		if colors, ok := parse_workspace_button_colors(value); ok {
			config.bar.inactive_workspace = colors
		}
	case "urgent_workspace":
		if colors, ok := parse_workspace_button_colors(value); ok {
			config.bar.urgent_workspace = colors
		}
	case "binding_mode":
		if colors, ok := parse_workspace_button_colors(value); ok {
			config.bar.binding_mode = colors
		}
	}
}

apply_client_value :: proc(key: string, value: string, config: ^render.Renderer_Config) {
	switch key {
	case "focused":
		if colors, ok := parse_client_colors(value); ok {
			config.client.focused = colors
		}
	case "focused_inactive":
		if colors, ok := parse_client_colors(value); ok {
			config.client.focused_inactive = colors
		}
	case "unfocused":
		if colors, ok := parse_client_colors(value); ok {
			config.client.unfocused = colors
		}
	case "urgent":
		if colors, ok := parse_client_colors(value); ok {
			config.client.urgent = colors
		}
	case "focused_tab_title":
		if colors, ok := parse_client_colors(value); ok {
			config.client.focused_tab_title = colors
		}
	case "background":
		if r, g, b, ok := parse_hex_color(value); ok {
			config.client.background = render.RGB_Color{r, g, b}
		}
	}
}

apply_input_value :: proc(key: string, value: string, config: ^Config) {
	switch key {
	case "mod", "mod_key":
		config.mod_key = parse_mod_key(value, config.mod_key)
	case "quit":
		config.bindings.quit = value
	case "split_right":
		config.bindings.split_right = value
	case "split_down":
		config.bindings.split_down = value
	case "open_pane":
		config.bindings.open_pane = value
	case "close_pane":
		config.bindings.close_pane = value
	case "dump_tree":
		config.bindings.dump_tree = value
	case "resize_mode":
		config.bindings.resize_mode = value
	case "fullscreen_toggle":
		config.bindings.fullscreen_toggle = value
	case "layout_stacking":
		config.bindings.layout_stacking = value
	case "layout_tabbed":
		config.bindings.layout_tabbed = value
	case "layout_toggle_split", "rotate_layout":
		config.bindings.layout_toggle_split = value
	case "focus_left":
		config.bindings.focus_left = value
	case "focus_down":
		config.bindings.focus_down = value
	case "focus_up":
		config.bindings.focus_up = value
	case "focus_right":
		config.bindings.focus_right = value
	case "move_left":
		config.bindings.move_left = value
	case "move_down":
		config.bindings.move_down = value
	case "move_up":
		config.bindings.move_up = value
	case "move_right":
		config.bindings.move_right = value
	case "workspace_1":
		config.bindings.workspace_1 = value
	case "workspace_2":
		config.bindings.workspace_2 = value
	case "workspace_3":
		config.bindings.workspace_3 = value
	case "workspace_4":
		config.bindings.workspace_4 = value
	case "workspace_5":
		config.bindings.workspace_5 = value
	case "workspace_6":
		config.bindings.workspace_6 = value
	case "workspace_7":
		config.bindings.workspace_7 = value
	case "workspace_8":
		config.bindings.workspace_8 = value
	case "workspace_9":
		config.bindings.workspace_9 = value
	case "move_to_workspace_1":
		config.bindings.move_to_workspace_1 = value
	case "move_to_workspace_2":
		config.bindings.move_to_workspace_2 = value
	case "move_to_workspace_3":
		config.bindings.move_to_workspace_3 = value
	case "move_to_workspace_4":
		config.bindings.move_to_workspace_4 = value
	case "move_to_workspace_5":
		config.bindings.move_to_workspace_5 = value
	case "move_to_workspace_6":
		config.bindings.move_to_workspace_6 = value
	case "move_to_workspace_7":
		config.bindings.move_to_workspace_7 = value
	case "move_to_workspace_8":
		config.bindings.move_to_workspace_8 = value
	case "move_to_workspace_9":
		config.bindings.move_to_workspace_9 = value
	}
}

apply_background_value :: proc(value: string, config: ^render.Renderer_Config) {
	if value == "none" {
		config.background_set = false
		return
	}

	if r, g, b, ok := parse_hex_color(value); ok {
		config.background_set = true
		config.background_r = r
		config.background_g = g
		config.background_b = b
	}
}

apply_foreground_value :: proc(value: string, config: ^render.Renderer_Config) {
	if value == "none" {
		config.foreground_set = false
		return
	}

	if r, g, b, ok := parse_hex_color(value); ok {
		config.foreground_set = true
		config.foreground_r = r
		config.foreground_g = g
		config.foreground_b = b
	}
}

apply_palette_value :: proc(key: string, value: string, config: ^render.Renderer_Config) {
	index, ok := palette_index(key)
	if !ok {
		return
	}

	if r, g, b, color_ok := parse_hex_color(value); color_ok {
		config.palette[index] = render.RGB_Color{r, g, b}
	}
}

palette_index :: proc(key: string) -> (int, bool) {
	switch key {
	case "black", "color0", "colour0", "ansi_0": return 0, true
	case "red", "color1", "colour1", "ansi_1": return 1, true
	case "green", "color2", "colour2", "ansi_2": return 2, true
	case "yellow", "color3", "colour3", "ansi_3": return 3, true
	case "blue", "color4", "colour4", "ansi_4": return 4, true
	case "magenta", "purple", "color5", "colour5", "ansi_5": return 5, true
	case "cyan", "color6", "colour6", "ansi_6": return 6, true
	case "white", "color7", "colour7", "ansi_7": return 7, true
	case "bright_black", "bright-black", "color8", "colour8", "ansi_8": return 8, true
	case "bright_red", "bright-red", "color9", "colour9", "ansi_9": return 9, true
	case "bright_green", "bright-green", "color10", "colour10", "ansi_10": return 10, true
	case "bright_yellow", "bright-yellow", "color11", "colour11", "ansi_11": return 11, true
	case "bright_blue", "bright-blue", "color12", "colour12", "ansi_12": return 12, true
	case "bright_magenta", "bright-magenta", "bright_purple", "bright-purple", "color13", "colour13", "ansi_13": return 13, true
	case "bright_cyan", "bright-cyan", "color14", "colour14", "ansi_14": return 14, true
	case "bright_white", "bright-white", "color15", "colour15", "ansi_15": return 15, true
	}

	return 0, false
}

clean_value :: proc(value: string) -> string {
	trimmed := strings.trim_space(value)
	if len(trimmed) >= 2 {
		first := trimmed[0]
		last := trimmed[len(trimmed) - 1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			return trimmed[1:len(trimmed) - 1]
		}
	}
	return trimmed
}

find_char :: proc(value: string, target: byte) -> int {
	for index in 0 ..< len(value) {
		if value[index] == target {
			return index
		}
	}
	return -1
}

parse_mod_key :: proc(value: string, default_value: input.Mod_Key) -> input.Mod_Key {
	switch value {
	case "alt", "option", "opt":
		return .Alt
	case "super", "gui", "cmd", "command", "meta":
		return .Super
	}
	return default_value
}

parse_int :: proc(value: string) -> (int, bool) {
	if value == "" {
		return 0, false
	}

	result := 0
	for index in 0 ..< len(value) {
		if value[index] < '0' || value[index] > '9' {
			return 0, false
		}
		result = result * 10 + int(value[index] - '0')
	}
	return result, true
}

parse_client_colors :: proc(value: string) -> (render.Client_Color, bool) {
	words: [5]string
	remaining := value
	for index in 0 ..< len(words) {
		word, rest, ok := next_word(remaining)
		if !ok {
			return render.Client_Color{}, false
		}
		words[index] = word
		remaining = rest
	}

	border_r, border_g, border_b, border_ok := parse_hex_color(words[0])
	bg_r, bg_g, bg_b, bg_ok := parse_hex_color(words[1])
	text_r, text_g, text_b, text_ok := parse_hex_color(words[2])
	indicator_r, indicator_g, indicator_b, indicator_ok := parse_hex_color(words[3])
	child_r, child_g, child_b, child_ok := parse_hex_color(words[4])
	if !(border_ok && bg_ok && text_ok && indicator_ok && child_ok) {
		return render.Client_Color{}, false
	}

	return render.Client_Color {
		border = render.RGB_Color{border_r, border_g, border_b},
		background = render.RGB_Color{bg_r, bg_g, bg_b},
		text = render.RGB_Color{text_r, text_g, text_b},
		indicator = render.RGB_Color{indicator_r, indicator_g, indicator_b},
		child_border = render.RGB_Color{child_r, child_g, child_b},
	}, true
}

parse_workspace_button_colors :: proc(value: string) -> (render.Workspace_Button_Colors, bool) {
	first, rest, ok := next_word(value)
	if !ok {
		return render.Workspace_Button_Colors{}, false
	}
	second, rest2, ok2 := next_word(rest)
	if !ok2 {
		return render.Workspace_Button_Colors{}, false
	}
	third, _, ok3 := next_word(rest2)
	if !ok3 {
		return render.Workspace_Button_Colors{}, false
	}

	border_r, border_g, border_b, border_ok := parse_hex_color(first)
	bg_r, bg_g, bg_b, bg_ok := parse_hex_color(second)
	text_r, text_g, text_b, text_ok := parse_hex_color(third)
	if !(border_ok && bg_ok && text_ok) {
		return render.Workspace_Button_Colors{}, false
	}

	return render.Workspace_Button_Colors {
		border = render.RGB_Color{border_r, border_g, border_b},
		background = render.RGB_Color{bg_r, bg_g, bg_b},
		text = render.RGB_Color{text_r, text_g, text_b},
	}, true
}

next_word :: proc(value: string) -> (string, string, bool) {
	start := 0
	for start < len(value) && is_space(value[start]) {
		start += 1
	}
	if start >= len(value) {
		return "", "", false
	}

	end := start
	for end < len(value) && !is_space(value[end]) {
		end += 1
	}

	return value[start:end], value[end:], true
}

is_space :: proc(value: byte) -> bool {
	return value == ' ' || value == '\t'
}

parse_hex_color :: proc(value: string) -> (u8, u8, u8, bool) {
	color := value
	if len(color) == 7 && color[0] == '#' {
		red, red_ok := parse_hex_byte(color[1:3])
		green, green_ok := parse_hex_byte(color[3:5])
		blue, blue_ok := parse_hex_byte(color[5:7])
		return red, green, blue, red_ok && green_ok && blue_ok
	}
	if len(color) == 8 && color[:2] == "0x" {
		red, red_ok := parse_hex_byte(color[2:4])
		green, green_ok := parse_hex_byte(color[4:6])
		blue, blue_ok := parse_hex_byte(color[6:8])
		return red, green, blue, red_ok && green_ok && blue_ok
	}
	return 0, 0, 0, false
}

parse_hex_byte :: proc(value: string) -> (u8, bool) {
	if len(value) != 2 {
		return 0, false
	}

	hi, hi_ok := hex_digit(value[0])
	lo, lo_ok := hex_digit(value[1])
	return u8(hi * 16 + lo), hi_ok && lo_ok
}

hex_digit :: proc(value: byte) -> (int, bool) {
	switch {
	case value >= '0' && value <= '9':
		return int(value - '0'), true
	case value >= 'a' && value <= 'f':
		return int(value - 'a') + 10, true
	case value >= 'A' && value <= 'F':
		return int(value - 'A') + 10, true
	}
	return 0, false
}
