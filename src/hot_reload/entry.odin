package hot_reload

import "core:dynlib"
import "core:log"
import "core:thread"

// ============================================================
// TESTING KNOB -- swap this while the real entry-point
// convention is still being nailed down. Not final.
// ============================================================
RELOAD_ENTRY_PROC :: "odin_online"

Reload_Entry_Proc :: proc()

// The single line. Spawns a thread that owns everything from here:
// build -> load -> call entry -> watch -> rebuild -> reload, forever.
//
// No package state. The only thing handed across the thread boundary
// is the directory string itself, via poly data -- not a heap struct,
// not a global. Everything else (lib name, output path, handle, entry
// proc) is derived fresh from `path` or lives only as a local on the
// thread's own stack for as long as that thread runs.
start :: proc(path: string) {
	thread.create_and_start_with_poly_data(path, run)
}

run :: proc(path: string) {
	handle: dynlib.Library
	entry: Reload_Entry_Proc

	if !reload(path, &handle, &entry) {
		log.error("hot_reload: initial build/load failed for", path)
		return
	}
	entry()

	events_handle := events_os_open(path)
	buffer: [4096]u8

	for {
		n := events_os_track(events_handle, buffer[:])
		if n <= 0 do continue

		offset := 0
		changed := false
		for offset < n {
			action, next_offset := events_os_cast(buffer[:], offset)
			if next_offset == offset do break
			offset = next_offset
			changed = true
			_ = action
		}

		if !changed do continue

		if reload(path, &handle, &entry) {
			entry()
		} else {
			log.error("hot_reload: rebuild/reload failed, keeping previous library running")
		}
	}
}
