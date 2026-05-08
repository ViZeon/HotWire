package efsw

import "base:runtime"
import "core:thread"
import "core:sync"
import "core:strings"

Event_Type :: enum {
	Created,
	Deleted,
	Modified,
	Moved,
	Attrib,
}

Event :: struct {
	dir:      string, // directory path
	file:     string, // filename (relative to dir)
	type:     Event_Type,
	old_file: string, // only valid for .Moved
}

Callback :: #type proc(event: Event)

Watcher :: struct {
	allocator: runtime.Allocator,
	callback:  Callback,
	thread:    ^thread.Thread,
	mu:        sync.Mutex,
	running:   bool,
	impl:      rawptr,
}

init :: proc(callback: Callback, allocator := context.allocator) -> ^Watcher {
	w := new(Watcher, allocator)
	w.allocator = allocator
	w.callback = callback
	w.running = false
	w.impl = nil

	when ODIN_OS == .Linux {
		w.impl = _init_linux(w)
	} else when ODIN_OS == .Windows {
		w.impl = _init_windows(w)
	} else when ODIN_OS == .Darwin {
		w.impl = _init_darwin(w)
	} else {
		panic("efsw: unsupported platform")
	}

	return w
}

add_watch :: proc(w: ^Watcher, path: string) -> bool {
	when ODIN_OS == .Linux {
		return _add_watch_linux(w, path)
	} else when ODIN_OS == .Windows {
		return _add_watch_windows(w, path)
	} else when ODIN_OS == .Darwin {
		return _add_watch_darwin(w, path)
	}
	return false
}

remove_watch :: proc(w: ^Watcher, path: string) -> bool {
	when ODIN_OS == .Linux {
		return _remove_watch_linux(w, path)
	} else when ODIN_OS == .Windows {
		return _remove_watch_windows(w, path)
	} else when ODIN_OS == .Darwin {
		return _remove_watch_darwin(w, path)
	}
	return false
}

start :: proc(w: ^Watcher) {
	sync.mutex_lock(&w.mu)
	if w.running {
		sync.mutex_unlock(&w.mu)
		return
	}
	w.running = true
	sync.mutex_unlock(&w.mu)

	w.thread = thread.create(proc(t: ^thread.Thread) {
		w := (^Watcher)(t.data)
		when ODIN_OS == .Linux {
			_run_linux(w)
		} else when ODIN_OS == .Windows {
			_run_windows(w)
		} else when ODIN_OS == .Darwin {
			_run_darwin(w)
		}
	})
	w.thread.data = rawptr(w)
	thread.start(w.thread)
}

stop :: proc(w: ^Watcher) {
	sync.mutex_lock(&w.mu)
	if !w.running {
		sync.mutex_unlock(&w.mu)
		return
	}
	w.running = false
	sync.mutex_unlock(&w.mu)

	when ODIN_OS == .Linux {
		_stop_linux(w)
	} else when ODIN_OS == .Windows {
		_stop_windows(w)
	} else when ODIN_OS == .Darwin {
		_stop_darwin(w)
	}

	if w.thread != nil {
		thread.join(w.thread)
		thread.destroy(w.thread)
		w.thread = nil
	}
}

destroy :: proc(w: ^Watcher) {
	stop(w)

	when ODIN_OS == .Linux {
		_destroy_linux(w)
	} else when ODIN_OS == .Windows {
		_destroy_windows(w)
	} else when ODIN_OS == .Darwin {
		_destroy_darwin(w)
	}

	free(w, w.allocator)
}