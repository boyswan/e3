package app

main :: proc() {
	app: App
	init_app(&app)

	execute_command(&app, command_split_horizontal())
	execute_command(&app, command_split_vertical())
	execute_command(&app, command_switch_workspace(2))
	execute_command(&app, command_split_vertical())
	execute_command(&app, command_switch_workspace(1))

	width, height := terminal_size_or_default(80, 24)
	screen := make_screen_buffer(width, height)
	defer destroy_screen_buffer(&screen)

	terminal_enter_app_screen()
	defer terminal_leave_app_screen()

	mode: Terminal_Mode
	terminal_enter_raw_mode(&mode)
	defer terminal_restore_mode(&mode)

	running := true
	for running {
		new_width, new_height := terminal_size_or_default(80, 24)
		if new_width != screen.width || new_height != screen.height {
			destroy_screen_buffer(&screen)
			screen = make_screen_buffer(new_width, new_height)
		}

		render_app(&screen, &app, Rect{x = 0, y = 0, width = screen.width, height = screen.height})
		terminal_flush_screen(&screen)

		action := read_input_action()
		switch action.kind {
		case .None:
			// Ignore unknown input.
		case .Quit:
			running = false
		case .Command:
			execute_command(&app, action.command)
		}
	}
}
