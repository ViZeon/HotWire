package watcher

import "core:fmt"
import "core:os"
import "core:sys/linux"

when ODIN_OS == .Linux {
	watch_dir :: proc(path: cstring, file_updated: ^bool) {
		fd, _ := linux.inotify_init()
		file_updated^ = false

		IN_MODIFY :: 0x00000002
		IN_CREATE :: 0x00000100
		IN_DELETE :: 0x00000200

		IN_MOVED_FROM :: 0x00000040
		IN_MOVED_TO :: 0x00000080

		mask := transmute(bit_set[linux.Inotify_Event_Bits;u32])(u32(
				IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO,
			))
		linux.inotify_add_watch(fd, path, mask)

		buffer: [1024]u8
		fmt.println("Watching directory (Linux) in background...")

		for {
			n, _ := linux.read(fd, buffer[:])
			if n <= 0 do continue

			// Parse the buffer
			offset: u32 = 0
			for offset < u32(n) {
				// Cast the current position in the buffer to an Inotify_Event pointer
				event := cast(^linux.Inotify_Event)&buffer[offset]

				// Determine the action
				action: Action
				event_mask := u32(transmute(u32)event.mask)
				switch {
				case (event_mask & IN_MODIFY) != 0:     action = .Modified
				case (event_mask & IN_CREATE) != 0:     action = .Created
				case (event_mask & IN_DELETE) != 0:     action = .Deleted
				case (event_mask & IN_MOVED_FROM) != 0: action = .RenamedFrom // or a new .Renamed
				case (event_mask & IN_MOVED_TO) != 0:   action = .RenamedTo
				}

				// Extract the file name (if one exists)
				if event.len > 0 {
					// The name starts immediately after the struct
					name_ptr := cast(cstring)&buffer[offset + size_of(linux.Inotify_Event)]
					fmt.printf("[%s] %s\n", action, name_ptr)
					file_updated^ = true
				}

				// Move to the next event in the buffer
				offset += size_of(linux.Inotify_Event) + event.len
			}
		}
	}


	lib_update :: proc(lib_counter: ^int, path: string, tmp_path: string) {
		// Linux: load a copy so the build can overwrite lib.so

		tmp := fmt.tprintf(path, lib_counter)
		lib_counter^ += 1

        // replace the whole read write file thing with just a copy command

        os.copy_file("source.so", "dest.so")

		fmt.println("library written successfully.")

	}

    lib_compile:: proc () {
            //compile_command := fmt.tprintf("odin build hotcode/%v.odin -build-mode:dll -out:hotcode/%v -file", hl.name, hl.dirs[hl.idx])
    }
}
