package hot_reload

import "core:dynlib"
import "core:log"

// Rebuilds and reloads the library at lib_path(path). `handle` and
// `entry` are owned by the caller's own stack frame (see run() in
// entry.odin) -- this package holds nothing persistent itself.
//
// Old handle is unloaded first. On Linux this is safe even though
// build() already overwrote the file on disk -- the actual
// constraint isn't "can't overwrite a loaded .so", it's "must drop
// the old dlopen handle before re-opening to see fresh symbols."
reload :: proc(path: string, handle: ^dynlib.Library, entry: ^Reload_Entry_Proc) -> bool {
	if !build(path) {
		log.error("hot_reload: build failed for", path)
		return false
	}

	if handle^ != nil {
		dynlib.unload_library(handle^)
		handle^ = nil
		entry^ = nil
	}

	new_handle, ok := dynlib.load_library(lib_path(path))
	if !ok {
		log.error("hot_reload: failed to load", lib_path(path), "-", dynlib.last_error())
		return false
	}

	sym, sym_ok := dynlib.symbol_address(new_handle, RELOAD_ENTRY_PROC)
	if !sym_ok {
		log.error("hot_reload: entry proc", RELOAD_ENTRY_PROC, "not found in", lib_path(path))
		dynlib.unload_library(new_handle)
		return false
	}

	handle^ = new_handle
	entry^ = cast(Reload_Entry_Proc)sym
	return true
}
