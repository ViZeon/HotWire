package main

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import "core:sync"
import "core:thread"

import "core:os"
import "core:sys/linux"
import "core:sys/windows"

import "efsw"
import SDL "vendor:sdl3"

WIDTH :: 800
HEIGHT :: 720

img: ^SDL.Surface
window: ^SDL.Window
screen: ^SDL.Surface
plasma: []u32

frame_count := 0
last_time := SDL.GetTicks()

// --- Hot reload state ---
Library :: struct {
	__handle:    dynlib.Library,
	odin_online: proc(),
	print_this:  proc(_: string),
}


should_reload: b32
watcher: ^efsw.Watcher

update_fps :: proc() {
	frame_count += 1
	now := SDL.GetTicks()
	if now - last_time >= 1000 {
		SDL.SetWindowTitle(window, fmt.ctprintf("Plasma - FPS: %d", frame_count))
		frame_count = 0
		last_time = now
	}
}

cleanup :: proc() {
	SDL.DestroySurface(img)
	delete(plasma)
	SDL.DestroyWindow(window)
	SDL.Quit()
}

xorshift32 :: proc(state: ^u32) -> u32 {
	state^ ~= state^ << 13
	state^ ~= state^ >> 17
	state^ ~= state^ << 5
	return state^
}

generate_plasma :: proc(buf: []u32, w, h: int) {
	rng_state: u32 = 0x12345678
	a1 := f32(xorshift32(&rng_state) % 1000) / 1000.0 * math.TAU
	a2 := f32(xorshift32(&rng_state) % 1000) / 1000.0 * math.TAU
	a3 := f32(xorshift32(&rng_state) % 1000) / 1000.0 * math.TAU

	for y in 0 ..< h {
		for x in 0 ..< w {
			fx := f32(x) / f32(w)
			fy := f32(y) / f32(h)
			v :=
				math.sin(fx * 10.0 + a1) +
				math.sin(fy * 10.0 + a2) +
				math.sin((fx + fy) * 10.0 + a3)
			c := u8(math.clamp((v + 3.0) / 6.0 * 255.0, 0.0, 255.0))
			buf[y * w + x] = 0xFF000000 | (u32(c) << 16) | (u32(c) << 8) | u32(c)
		}
	}
}

SDLwindow :: proc() {
	if !SDL.Init(SDL.INIT_VIDEO) {
		log.panic("SDL_Init failed: %s\n", SDL.GetError())
	}

	window = SDL.CreateWindow("Plasma", WIDTH, HEIGHT, {})
	if window == nil {
		log.panic("CreateWindow failed: %s\n", SDL.GetError())
	}

	screen = SDL.GetWindowSurface(window)
	if screen == nil {
		log.panic("GetWindowSurface failed: %s\n", SDL.GetError())
	}

	plasma = make([]u32, WIDTH * HEIGHT)
	generate_plasma(plasma, WIDTH, HEIGHT)

	img = SDL.CreateSurfaceFrom(WIDTH, HEIGHT, screen.format, raw_data(plasma), WIDTH * 4)
	if img == nil {
		log.panic("CreateSurfaceFrom failed: %s\n", SDL.GetError())
	}
}

// --- File watcher callback (runs on watcher thread) ---
/*
file_event_callback :: proc(ev: efsw.Event) {
	fmt.printf("[CB] type=%v dir=%q file=%q old_file=%q\n", ev.type, ev.dir, ev.file, ev.old_file)
	
	if strings.contains(ev.file, ".odin") {
		if ev.type == .Modified || ev.type == .Created || ev.type == .Moved {
			sync.atomic_store(&should_reload, true)
		}
	}
	delete(ev.dir)
	delete(ev.file)
	if ev.old_file != "" { delete(ev.old_file) }
}
*/

// --- Library loading ---
load_library :: proc(lib: ^Library) -> bool {
	if lib.__handle != nil {
		dynlib.unload_library(lib.__handle)
		lib.__handle = nil
	}

	// IMPORTANT: On Linux you cannot overwrite a loaded .so.
	// If your build writes directly to lib.so, copy it to a temp name first.
	// For now we assume the build handles this, or you adjust the path.
	handle, ok := dynlib.load_library("lib.so")
	if !ok {
		log.error("Failed to load library:", dynlib.last_error())
		return false
	}
	lib.__handle = handle

	sym, sym_ok := dynlib.symbol_address(handle, "odin_online")
	if sym_ok {lib.odin_online = cast(proc())sym}

	sym, sym_ok = dynlib.symbol_address(handle, "print_this")
	if sym_ok {lib.print_this = cast(proc(_: string))sym}

	log.info("Library loaded")
	return true
}

main :: proc() {
	context.logger = log.create_console_logger()
	log.debug("Hello")

	// 2. Create and start the background thread
	t := thread.create(watcher_thread_proc)
	if t != nil {
		thread.start(t)
	}


	/*
	// Setup watcher BEFORE SDL so we don't miss early builds
	watcher = efsw.init(file_event_callback)
	if watcher == nil {
		log.panic("Failed to create watcher")
	}

	// Watch the directory containing your DLL
	// Adjust this path to match your actual output directory
	watch_path := "./watch_me"
	if !efsw.add_watch(watcher, watch_path) {
		log.warnf("Failed to add watch for '%s'. Does the directory exist?", watch_path)
	} else {
		efsw.start(watcher)
		log.infof("Watching '%s' for changes...", watch_path)
	}
	*/

	SDLwindow()

	// Load initial library
	lib: Library
	if !load_library(&lib) {
		log.panic("Failed to load initial library")
	}

	main_loop: for {
		// Check for hot reload (main thread)
		if sync.atomic_load(&should_reload) {
			sync.atomic_store(&should_reload, false)
			log.info("Hot reload triggered")
			load_library(&lib)
		}

		ev: SDL.Event
		for SDL.PollEvent(&ev) {
			#partial switch ev.type {
			case .QUIT:
				break main_loop
			case .KEY_DOWN:
				if ev.key.scancode == .ESCAPE do break main_loop
			}
		}

		SDL.BlitSurface(img, nil, screen, nil)
		SDL.UpdateWindowSurface(window)
		update_fps()
	}

	//watch_dir("./watch_me")
	/*

	if lib.__handle != nil {
		dynlib.unload_library(lib.__handle)
	}

	cleanup()
	if watcher != nil {
		efsw.destroy(watcher)
	}

*/


	// 1. Create a wrapper procedure that matches what Odin's thread system expects
	watcher_thread_proc :: proc(t: ^thread.Thread) {
		watch_dir(".")

	}


	when ODIN_OS == .Linux {
		watch_dir :: proc(path: cstring) {
			fd, _ := linux.inotify_init()

			IN_MODIFY :: 0x00000002
			IN_CREATE :: 0x00000100
			IN_DELETE :: 0x00000200

			mask := transmute(bit_set[linux.Inotify_Event_Bits;u32])(u32(
					IN_CREATE | IN_DELETE | IN_MODIFY,
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
					action := "Unknown"
					event_mask := u32(transmute(u32)event.mask)
					if (event_mask & IN_MODIFY) != 0 do action = "Modified"
					else if (event_mask & IN_CREATE) != 0 do action = "Created"
					else if (event_mask & IN_DELETE) != 0 do action = "Deleted"

					// Extract the file name (if one exists)
					if event.len > 0 {
						// The name starts immediately after the struct
						name_ptr := cast(cstring)&buffer[offset + size_of(linux.Inotify_Event)]
						fmt.printf("[%s] %s\n", action, name_ptr)
if action == "Modified" {
    fmt.println("--> Attempting to build...")
    
    // Make sure to put your actual script name here!
    p, err := os.process_start({command = {"sh", "./build_linux.sh"}})

    if err != nil {
        fmt.println("--> BUILD ERROR:", err)
    } else {
        // The _, _ = tells Odin it's okay to ignore the results
        _, _ = os.process_wait(p) 
        fmt.println("--> Build finished!")
    }
    
    sync.atomic_store(&should_reload, true)
}

					}

					// Move to the next event in the buffer
					offset += size_of(linux.Inotify_Event) + event.len
				}
			}
		}
	}

	when ODIN_OS == .Windows {
		watch_dir :: proc(path: string) {
			dir_handle := windows.CreateFileA(
				raw_data(path),
				windows.FILE_LIST_DIRECTORY,
				windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
				nil,
				windows.OPEN_EXISTING,
				windows.FILE_FLAG_BACKUP_SEMANTICS,
				nil,
			)

			// Note: Windows requires the buffer to be aligned properly.
			// Using a slice of u32 ensures 4-byte alignment.
			buffer: [1024]u32
			bytes_returned: u32
			fmt.println("Watching directory (Windows) in background...")

			for {
				windows.ReadDirectoryChangesW(
					dir_handle,
					&buffer[0],
					u32(len(buffer) * size_of(u32)),
					false,
					windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME,
					&bytes_returned,
					nil,
					nil,
				)

				if bytes_returned <= 0 do continue

				// Parse the buffer
				offset: u32 = 0
				for {
					// Cast the current position to a FILE_NOTIFY_INFORMATION pointer
					// We cast buffer to ^u8 first to do byte-level math with the offset
					raw_ptr := cast(^u8)&buffer[0]
					info := cast(^windows.FILE_NOTIFY_INFORMATION)&raw_ptr[offset]

					// Determine the action
					action := "Unknown"
					switch info.Action {
					case windows.FILE_ACTION_ADDED:
						action = "Created"
					case windows.FILE_ACTION_REMOVED:
						action = "Deleted"
					case windows.FILE_ACTION_MODIFIED:
						action = "Modified"
					case windows.FILE_ACTION_RENAMED_OLD_NAME:
						action = "Renamed (Old)"
					case windows.FILE_ACTION_RENAMED_NEW_NAME:
						action = "Renamed (New)"
					}

					// FileNameLength is in bytes. Divide by 2 to get the number of WCHARs (UTF-16 characters)
					name_len_chars := info.FileNameLength / 2

					fmt.printf("[%s] ", action)
					// Print the UTF-16 characters one by one
					for i in 0 ..< name_len_chars {
						fmt.printf("%r", rune(info.FileName[i]))
					}
					fmt.println()

					// Move to the next event, or break if this is the last one
					if info.NextEntryOffset == 0 do break
					offset += info.NextEntryOffset
				}
			}
		}
	}

}
