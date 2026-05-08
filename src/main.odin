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

import "watcher"
import SDL "vendor:sdl3"

WIDTH :: 1280
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


	// 1. Create a wrapper procedure that matches what Odin's thread system expects
	watcher_thread_proc :: proc(t: ^thread.Thread) {
		watcher.watch_dir(".")

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