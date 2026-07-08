package hot_reload

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"

Action :: enum {
    Modified,
    Created,
    Deleted,
    RenamedFrom,
    RenamedTo,
}

// Internal struct to pass data to the background thread
Watcher_Data :: struct {
    path: string,
    lib_handle: ^dynlib.Library,
}

// The ONLY function the user needs to call.
// path: directory to watch
// lib_handle: OPTIONAL pointer to their dynlib.Library handle. If provided, we load it.
watch :: proc(path: string, lib_handle: ^dynlib.Library = nil) {
    // Allocate context on the heap so the thread can access it after this function returns
    data := new(Watcher_Data)
    data.path = path
    data.lib_handle = lib_handle

    // Standard Odin way to pass data to a thread
    context.user_ptr = data

    // Create and start the background thread (exactly as you did in main)
    t := thread.create(watcher_thread_proc)
    if t != nil {
        thread.start(t)
    }
}

// Internal thread procedure
watcher_thread_proc :: proc(t: ^thread.Thread) {
    // Retrieve the pointer from the thread's context
    data := cast(^Watcher_Data)context.user_ptr
    
    handle := events_os_open(data.path)
    buffer: [4096]u8

    for {
        n := events_os_track(handle, buffer[:])
        if n <= 0 do continue

        offset := 0
        for offset < n {
            action, next_offset := events_os_cast(buffer[:], offset)
            if next_offset == offset do break // Windows sentinel: no more records
            
            // Automatically trigger build and load on modify or create
            if action == .Modified || action == .Created {
                lib_update(data.path, data.lib_handle)
            }
            
            offset = next_offset
        }
    }
}

lib_path_update :: proc(path, lib_name: string) -> string {
    full_path, err := filepath.join({path, lib_name}, context.allocator)
    if err != nil {
        fmt.println("Path join error:", err)
        return ""
    }
    return full_path
}

lib_update :: proc(path: string, lib_handle: ^dynlib.Library = nil) {
    lib_name := folder_name_last(path)
    ext := lib_extension()
    lib_name = strings.concatenate({lib_name, ext})
    
    full_path := lib_path_update(path, lib_name)

    // 1. Compile
    lib_compile(path, full_path)

    // 2. Unload old handle if it exists and was provided
    if lib_handle != nil && lib_handle^ != nil {
        dynlib.unload_library(lib_handle^)
        lib_handle^ = nil
    }

    // 3. Load the newly built library if handle was provided
    if lib_handle != nil {
        load_path := full_path
        
        // Handle Linux .so overwrite issue statelessly
        if ext == ".so" {
            temp_path := fmt.tprintf("%s_loaded%s", strings.trim_suffix(full_path, ext), ext)
            err_cp := os.copy_file(full_path, temp_path)
            load_path = temp_path
        }

        handle, ok := dynlib.load_library(load_path)
        if ok do lib_handle^ = handle
    }

    fmt.println("Path read successfully.", full_path)
}

lib_compile :: proc(path: string, full_path: string) {
    out_flag := fmt.tprintf("-out:%s", full_path)
    p, err := os.process_start({command = {"odin", "build", path, "-build-mode:dll", out_flag}})
    if err != nil {
        fmt.println("Compile error:", err)
        return
    }
    proc_state, proc_err := os.process_wait(p)
}

folder_name_last :: proc(path: string) -> string {
    clean := strings.trim_right(path, "/\\")
    if filepath.ext(clean) != "" {
        clean = filepath.dir(clean)
    }
    return filepath.base(clean)
}