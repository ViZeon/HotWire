package efsw

import "core:strings"
import "core:path/filepath"
import "core:mem"
import "core:fmt"

when ODIN_OS == .Linux {

foreign import libc "system:c"

@(default_calling_convention="c")
foreign libc {
	inotify_init      :: proc() -> i32 ---
	inotify_add_watch :: proc(fd: i32, pathname: cstring, mask: u32) -> i32 ---
	inotify_rm_watch  :: proc(fd: i32, wd: i32) -> i32 ---
	read              :: proc(fd: i32, buf: rawptr, count: uint) -> int ---
	close             :: proc(fd: i32) -> i32 ---
}

IN_ACCESS        :: u32(0x00000001)
IN_MODIFY        :: u32(0x00000002)
IN_ATTRIB        :: u32(0x00000004)
IN_CLOSE_WRITE   :: u32(0x00000008)
IN_MOVED_FROM    :: u32(0x00000040)
IN_MOVED_TO      :: u32(0x00000080)
IN_CREATE        :: u32(0x00000100)
IN_DELETE        :: u32(0x00000200)
IN_DELETE_SELF   :: u32(0x00000400)
IN_MOVE_SELF     :: u32(0x00000800)
IN_IGNORED       :: u32(0x00008000)
IN_ISDIR         :: u32(0x40000000)

WATCH_MASK :: IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO |
              IN_CLOSE_WRITE | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED

inotify_event :: struct #packed {
	wd:     i32,
	mask:   u32,
	cookie: u32,
	len:    u32,
}

_linux_watcher :: struct {
	fd:      i32,
	watches: map[i32]string,
	renames: map[u32]string,
}

_init_linux :: proc(w: ^Watcher) -> rawptr {
	lw := new(_linux_watcher, w.allocator)
	lw.fd = inotify_init()
	if lw.fd < 0 {
		free(lw, w.allocator)
		return nil
	}
	lw.watches = make(map[i32]string, 16, w.allocator)
	lw.renames = make(map[u32]string, 4, w.allocator)
	return rawptr(lw)
}

_add_watch_linux :: proc(w: ^Watcher, path: string) -> bool {
	lw := (^_linux_watcher)(w.impl)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	wd := inotify_add_watch(lw.fd, cpath, WATCH_MASK)
	if wd < 0 {
		return false
	}
	lw.watches[wd] = strings.clone(path, w.allocator)
	return true
}

_remove_watch_linux :: proc(w: ^Watcher, path: string) -> bool {
	lw := (^_linux_watcher)(w.impl)
	for wd, p in lw.watches {
		if p == path {
			inotify_rm_watch(lw.fd, wd)
			delete(p, w.allocator)
			delete_key(&lw.watches, wd)
			return true
		}
	}
	return false
}

_stop_linux :: proc(w: ^Watcher) {
	lw := (^_linux_watcher)(w.impl)
	if lw.fd >= 0 {
		close(lw.fd)
	}
}

_run_linux :: proc(w: ^Watcher) {
	lw := (^_linux_watcher)(w.impl)
	buf: [8192]u8

	for {
		n := read(lw.fd, &buf[0], len(buf))
		if n <= 0 {
			break
		}

		offset := 0
		for offset < int(n) {
			ev := (^inotify_event)(rawptr(&buf[offset]))

			name := ""
			if ev.len > 0 {
				name_ptr := rawptr(uintptr(rawptr(ev)) + size_of(inotify_event))
				name = strings.clone(string(cast(cstring)name_ptr), w.allocator)
			}

			dir := lw.watches[ev.wd]

			fmt.printf("[RAW] wd=%d mask=0x%08x cookie=%d len=%d dir=%q name=%q\n",
				ev.wd, ev.mask, ev.cookie, ev.len, dir, name)

			// Handle IN_IGNORED first — watch was removed
			if ev.mask & IN_IGNORED != 0 {
				if p, ok := lw.watches[ev.wd]; ok {
					delete(p, w.allocator)
					delete_key(&lw.watches, ev.wd)
				}
				offset += size_of(inotify_event) + int(ev.len)
				continue
			}

			// Clone dir so the callback owns it
			dir_clone := strings.clone(dir, w.allocator)

			// Use else-if chain: only ONE event type per raw inotify event
			if ev.mask & IN_CREATE != 0 {
				w.callback(Event{dir = dir_clone, file = name, type = .Created})
				if ev.mask & IN_ISDIR != 0 {
					sub, _ := filepath.join([]string{dir, name}, context.temp_allocator)
					_add_watch_linux(w, sub)
				}
			} else if ev.mask & IN_DELETE != 0 {
				w.callback(Event{dir = dir_clone, file = name, type = .Deleted})
			} else if ev.mask & IN_MODIFY != 0 {
				w.callback(Event{dir = dir_clone, file = name, type = .Modified})
			} else if ev.mask & IN_CLOSE_WRITE != 0 {
				w.callback(Event{dir = dir_clone, file = name, type = .Modified})
			} else if ev.mask & IN_ATTRIB != 0 {
				w.callback(Event{dir = dir_clone, file = name, type = .Attrib})
			} else if ev.mask & IN_MOVED_FROM != 0 {
				if ev.cookie != 0 {
					lw.renames[ev.cookie] = name
					// name is now owned by renames map, don't free it
					name = ""
				} else {
					w.callback(Event{dir = dir_clone, file = name, type = .Deleted})
				}
			} else if ev.mask & IN_MOVED_TO != 0 {
				if ev.cookie != 0 && ev.cookie in lw.renames {
					old := lw.renames[ev.cookie]
					w.callback(Event{
						dir      = dir_clone,
						file     = name,
						type     = .Moved,
						old_file = old,
					})
					delete(old, w.allocator)
					delete_key(&lw.renames, ev.cookie)
				} else {
					w.callback(Event{dir = dir_clone, file = name, type = .Created})
				}
			} else {
				// No recognized event type — free the cloned dir
				delete(dir_clone, w.allocator)
			}

			// Free name if it wasn't consumed by the renames map
			if name != "" {
				delete(name, w.allocator)
			}

			offset += size_of(inotify_event) + int(ev.len)
		}
	}
}

_destroy_linux :: proc(w: ^Watcher) {
	lw := (^_linux_watcher)(w.impl)
	if lw == nil { return }

	for _, path in lw.watches {
		delete(path, w.allocator)
	}
	delete(lw.watches)

	for _, name in lw.renames {
		delete(name, w.allocator)
	}
	delete(lw.renames)

	if lw.fd >= 0 {
		close(lw.fd)
	}
	free(lw, w.allocator)
}

}