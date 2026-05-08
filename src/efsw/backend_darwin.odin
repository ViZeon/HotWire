package efsw

when ODIN_OS == .Darwin {

// Stub: FSEvents backend reserved for future implementation.
// The public API in efsw.odin already dispatches here.

_init_darwin         :: proc(w: ^Watcher) -> rawptr { return nil }
_add_watch_darwin    :: proc(w: ^Watcher, path: string) -> bool { return false }
_remove_watch_darwin :: proc(w: ^Watcher, path: string) -> bool { return false }
_stop_darwin         :: proc(w: ^Watcher) {}
_run_darwin          :: proc(w: ^Watcher) {}
_destroy_darwin      :: proc(w: ^Watcher) {}

}