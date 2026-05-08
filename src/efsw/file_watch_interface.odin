package efsw

import "core:fmt"
import "core:time"


watch_start :: proc() {
	cb :: proc(ev: Event) {
		switch ev.type {
		case .Created:  fmt.printf("Created:  %s/%s\n", ev.dir, ev.file)
		case .Deleted:  fmt.printf("Deleted:  %s/%s\n", ev.dir, ev.file)
		case .Modified: fmt.printf("Modified: %s/%s\n", ev.dir, ev.file)
		case .Moved:    fmt.printf("Moved:    %s/%s -> %s/%s\n", ev.dir, ev.old_file, ev.dir, ev.file)
		case .Attrib:   fmt.printf("Attrib:   %s/%s\n", ev.dir, ev.file)
		}
		// NOTE: strings in Event are allocated with the watcher's allocator.
		// In production, free them here or use a scratch arena.
	}

	w := init(cb)
	defer destroy(w)

	if !add_watch(w, "./watch_me") {
		fmt.println("Failed to add watch")
		return
	}

	start(w)
	fmt.println("Watching for 30 seconds...")
	time.sleep(time.Second * 30)
	stop(w)
}