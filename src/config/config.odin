package config

import "core:fmt"
import "core:os"
import "core:strings"
import input "../input"
import render "../render"

Config :: struct {
	renderer: render.Renderer_Config,
	mod_key:  input.Mod_Key,
	bindings: input.Key_Bindings,
}

load_config :: proc() -> Config {
	config := Config {
		renderer = render.renderer_default_config(),
		mod_key = .Alt,
		bindings = input.key_bindings_default(),
	}
	path := find_config_path()
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

find_config_path :: proc() -> string {
	if os.exists("config.yaml") {
		return "config.yaml"
	}
	if os.exists("odin-play.yaml") {
		return "odin-play.yaml"
	}

	xdg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
	if xdg != "" {
		path := fmt.aprintf("%s/odin-play/config.yaml", xdg, allocator = context.temp_allocator)
		if os.exists(path) {
			return path
		}
	}

	home := os.get_env("HOME", context.temp_allocator)
	if home != "" {
		path := fmt.aprintf("%s/.config/odin-play/config.yaml", home, allocator = context.temp_allocator)
		if os.exists(path) {
			return path
		}
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

	if section == "input" || section == "keys" {
		apply_input_value(key, value, config)
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
	case "focus_left":
		config.bindings.focus_left = value
	case "focus_down":
		config.bindings.focus_down = value
	case "focus_up":
		config.bindings.focus_up = value
	case "focus_right":
		config.bindings.focus_right = value
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
