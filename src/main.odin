package main

import "watcher"
import SDL "vendor:sdl3"

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

main :: proc() {
	context.logger = log.create_console_logger()
	log.debug("Hello")



	// 2. Create and start the background thread
	t := thread.create(watcher_thread_proc)
	if t != nil {
		thread.start(t)
	}


	// 1. Create a wrapper procedure that matches what Odin's thread system expects
	watcher_thread_proc :: proc(t: ^thread.Thread) {
		watcher.watch_dir("./src/reloadable", &should_reload)

	}


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
			lib.odin_online()
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

}


// Next:
// - split method to load libraries, and make it handled for a list of libraries by hot reload
// - unify and store hot reload watching into a list, make a function to handle it
// - make a function to execute build scripts, also split by OS

// - usage should be one function supplying a pointer to the directory, should support sub-directories and multiples packages