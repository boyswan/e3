package app

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import posix "core:sys/posix"

foreign import process_libc "system:c"

foreign process_libc {
	tcgetpgrp :: proc(fd: c.int) -> c.int ---
}

when ODIN_OS == .Darwin {
	foreign import libproc "system:proc"

	foreign libproc {
		proc_name    :: proc(pid: c.int, buffer: rawptr, buffersize: u32) -> c.int ---
		proc_pidinfo :: proc(pid: c.int, flavor: c.int, arg: u64, buffer: rawptr, buffersize: c.int) -> c.int ---
	}

	DARWIN_PATH_MAX              :: 1024
	DARWIN_PROC_PIDVNODEPATHINFO :: c.int(9)

	Darwin_Vinfo_Stat :: struct {
		vst_dev:           u32,
		vst_mode:          u16,
		vst_nlink:         u16,
		vst_ino:           u64,
		vst_uid:           u32,
		vst_gid:           u32,
		vst_atime:         i64,
		vst_atimensec:     i64,
		vst_mtime:         i64,
		vst_mtimensec:     i64,
		vst_ctime:         i64,
		vst_ctimensec:     i64,
		vst_birthtime:     i64,
		vst_birthtimensec: i64,
		vst_size:          i64,
		vst_blocks:        i64,
		vst_blksize:       i32,
		vst_flags:         u32,
		vst_gen:           u32,
		vst_rdev:          u32,
		vst_qspare:        [2]i64,
	}

	Darwin_Vnode_Info :: struct {
		vi_stat: Darwin_Vinfo_Stat,
		vi_type: i32,
		vi_pad:  i32,
		vi_fsid: [2]i32,
	}

	Darwin_Vnode_Info_Path :: struct {
		vip_vi:   Darwin_Vnode_Info,
		vip_path: [DARWIN_PATH_MAX]u8,
	}

	Darwin_Proc_Vnodepath_Info :: struct {
		pvi_cdir: Darwin_Vnode_Info_Path,
		pvi_rdir: Darwin_Vnode_Info_Path,
	}

	#assert(size_of(Darwin_Vinfo_Stat) == 136)
	#assert(size_of(Darwin_Vnode_Info) == 152)
	#assert(size_of(Darwin_Vnode_Info_Path) == 1176)
	#assert(size_of(Darwin_Proc_Vnodepath_Info) == 2352)
}

// native_terminal_title supplies e3's no-configuration fallback when the
// terminal client has not provided an authoritative OSC title. It uses the
// abbreviated working directory and foreground process (for example "~ vim").
native_terminal_title :: proc(term: ^Terminal_Handle) -> string {
	if term == nil || !term.active || term.pty_fd < 0 {
		return "~"
	}

	foreground_pid := int(tcgetpgrp(c.int(term.pty_fd)))
	if foreground_pid <= 0 {
		foreground_pid = term.pid
	}

	cwd, cwd_ok := native_process_cwd(foreground_pid)
	if !cwd_ok && foreground_pid != term.pid {
		cwd, cwd_ok = native_process_cwd(term.pid)
	}

	display_cwd := "~"
	if cwd_ok && len(cwd) > 0 {
		display_cwd = abbreviate_home(cwd)
	}

	process_name, process_ok := native_process_name(foreground_pid)
	if !cwd_ok && !process_ok {
		return ""
	}
	if !process_ok || foreground_pid == term.pid || is_shell_name(process_name) {
		return strings.clone(display_cwd, context.temp_allocator)
	}

	return fmt.aprintf("%s %s", display_cwd, filepath.base(process_name), allocator = context.temp_allocator)
}

abbreviate_home :: proc(path: string) -> string {
	home_c := posix.getenv("HOME")
	if home_c == nil {
		return strings.clone(path, context.temp_allocator)
	}

	home := string(home_c)
	if path == home {
		return "~"
	}
	if len(path) > len(home) && strings.has_prefix(path, home) && path[len(home)] == '/' {
		return fmt.aprintf("~%s", path[len(home):], allocator = context.temp_allocator)
	}
	return strings.clone(path, context.temp_allocator)
}

is_shell_name :: proc(name: string) -> bool {
	base := filepath.base(name)
	return base == "sh" || base == "bash" || base == "zsh" || base == "fish" || base == "dash" || base == "ksh" || base == "nu"
}

native_process_name :: proc(pid: int) -> (string, bool) {
	when ODIN_OS == .Darwin {
		buffer: [256]u8
		length := proc_name(c.int(pid), raw_data(buffer[:]), u32(len(buffer)))
		if length <= 0 {
			return "", false
		}
		return strings.clone(string(buffer[:length]), context.temp_allocator), true
	} else when ODIN_OS == .Linux {
		path := fmt.aprintf("/proc/%d/comm", pid, allocator = context.temp_allocator)
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil || len(data) == 0 {
			return "", false
		}
		name := strings.trim_space(string(data))
		return strings.clone(name, context.temp_allocator), len(name) > 0
	} else {
		return "", false
	}
}

native_process_cwd :: proc(pid: int) -> (string, bool) {
	when ODIN_OS == .Darwin {
		info: Darwin_Proc_Vnodepath_Info
		result := proc_pidinfo(
			c.int(pid),
			DARWIN_PROC_PIDVNODEPATHINFO,
			0,
			&info,
			c.int(size_of(info)),
		)
		if result != c.int(size_of(info)) || info.pvi_cdir.vip_path[0] == 0 {
			return "", false
		}
		path := string(cstring(&info.pvi_cdir.vip_path[0]))
		return strings.clone(path, context.temp_allocator), true
	} else when ODIN_OS == .Linux {
		link := fmt.aprintf("/proc/%d/cwd", pid, allocator = context.temp_allocator)
		path, err := os.read_link(link, context.temp_allocator)
		if err != nil || len(path) == 0 {
			return "", false
		}
		return path, true
	} else {
		return "", false
	}
}
