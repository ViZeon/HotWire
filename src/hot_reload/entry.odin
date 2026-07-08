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

// The single line. The caller owns `path`. Writing a new string
// into the pointed-to location at runtime is how the watched
// directory gets changed -- hot_reload holds no state of its own
// beyond reading this one pointer each cycle.
start :: proc(path: ^string) {
	thread.create_and_start_with_poly_data(path, run)
}

run :: proc(path: ^string) {
	handle: dynlib.Library
	entry: Reload_Entry_Proc
	current := path^

	if !reload(current, &handle, &entry) {
		log.error("hot_reload: initial build/load failed for", current)
		return
	}
	entry()

	events_handle := events_os_open(current)
	buffer: [4096]u8

	for {
		n := events_os_track(events_handle, buffer[:])

		// TODO: events_os_track blocks until the OS reports a change
		// in `current`'s directory, so a pointer swap is only
		// noticed here -- i.e. whenever the *old* directory happens
		// to get an fs event. Revisit with a timeout so this is
		// responsive on its own, per the "modify later" call.
		if path^ != current {
			current = path^
			events_handle = events_os_open(current) // TODO: old handle is never closed -- no events_os_close exists yet
			if reload(current, &handle, &entry) {
				entry()
			} else {
				log.error("hot_reload: build/load failed after directory change to", current)
			}
			continue
		}

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

		if reload(current, &handle, &entry) {
			entry()
		} else {
			log.error("hot_reload: rebuild/reload failed, keeping previous library running")
		}
	}
}
