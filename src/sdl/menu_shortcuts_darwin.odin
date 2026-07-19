#+build darwin

package sdl

import cocoa "core:sys/darwin/Foundation"

// SDL creates standard macOS application and Window menus for unbundled
// executables. Their Command-key equivalents are handled by AppKit before SDL
// can emit keyboard events, so bindings such as Command+W and Command+H never
// reach e3. Keep the menus available, but remove their keyboard equivalents so
// configured Super bindings take priority while the e3 window is focused.
disable_native_menu_shortcuts :: proc() {
	app := cocoa.Application_sharedApplication()
	if app == nil {
		return
	}

	disable_menu_shortcuts(cocoa.Application_mainMenu(app))
}

disable_menu_shortcuts :: proc(menu: ^cocoa.Menu) {
	if menu == nil {
		return
	}

	empty := cocoa.AT("")
	item_count := int(cocoa.Menu_numberOfItems(menu))
	for index in 0 ..< item_count {
		item := cocoa.Menu_itemAtIndex(menu, cocoa.Integer(index))
		if item == nil {
			continue
		}

		cocoa.MenuItem_setKeyEquivalent(item, empty)
		disable_menu_shortcuts(cocoa.MenuItem_submenu(item))
	}
}
