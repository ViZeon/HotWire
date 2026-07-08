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

// Internal state managed entirely by the library
_internal_path: string
_internal_handle: dynlib.Library = nil
_internal_os_handle: Handle
_internal_extensions: []string

// The ONLY function the user needs to call.
// path: directory to watch
// extensions: OPTIONAL array of file extensions to trigger a reload (default is ".odin")
watch :: proc(path: string, extensions: []string = {".odin"}) {
    _internal_path = path
    _internal_extensions = extensions
    _internal_os_handle = events_os_open(path)

    fmt.println("Watcher started for:", path)

    // Create and start the background thread
    t := thread.create(watcher_thread_proc)
    if t != nil {
        thread.start(t)
    }
}

// Use this in main.odin to get the library handle and load your symbols
get_handle :: proc() -> dynlib.Library {
    return _internal_handle
}

// Internal thread procedure
watcher_thread_proc :: proc(t: ^thread.Thread) {
    handle := _internal_os_handle
    buffer: [4096]u8

    for {
        n := events_os_track(handle, buffer[:])
        if n <= 0 do continue

        offset := 0
        for offset < n {
            action, filename, next_offset := events_os_cast(buffer[:], offset)
            if next_offset == offset do break // Windows sentinel: no more records
            
            // Check if the file matches one of the allowed extensions
            is_allowed := false
            if len(filename) > 0 {
                for ext in _internal_extensions {
                    if strings.has_suffix(filename, ext) {
                        is_allowed = true
                        break
                    }
                }
            }
            
            if is_allowed {
                fmt.println("Detected action:", action, "on file:", filename)
                lib_update()
            }
            
            offset = next_offset
        }
    }
}

lib_update :: proc() {
    path := _internal_path
    lib_name := folder_name_last(path)
    ext := lib_extension()
    
    // Use stack buffers to avoid heap allocation in the thread
    // 1. Path WITHOUT extension (for the compiler)
    out_path_no_ext_buf: [256]u8
    out_path_no_ext := fmt.bprintf(out_path_no_ext_buf[:], "%s/%s", path, lib_name)

    // 2. Path WITH extension (for copying and loading)
    full_path_buf: [256]u8
    full_path := fmt.bprintf(full_path_buf[:], "%s%s", out_path_no_ext, ext)

    fmt.println("Attempting to build to:", full_path)

    // 1. Compile (abort if it fails)
    if !lib_compile(path, out_path_no_ext) {
        return
    }

    // List the directory to see what Odin actually created
    entries, dir_err := os.read_dir(path)
    if dir_err == nil {
        fmt.println("Directory", path, "contains:")
        for entry in entries {
            fmt.println(" -", entry.name())
        }
    }

    // 2. Unload old handle if it exists
    if _internal_handle != nil {
        dynlib.unload_library(_internal_handle)
        _internal_handle = nil
    }

    // 3. Load the newly built library
    load_path := full_path
    
    // Handle Linux .so overwrite issue internally
    if ext == ".so" {
        temp_path_buf: [256]u8
        temp_path := fmt.bprintf(temp_path_buf[:], "%s_loaded%s", out_path_no_ext, ext)
        
        copy_err := os.copy_file(full_path, temp_path)
        if copy_err != nil {
            fmt.println("Failed to copy .so file:", copy_err, "from", full_path, "to", temp_path)
            return
        }
        load_path = temp_path
    }

    h, ok := dynlib.load_library(load_path)
    if ok {
        _internal_handle = h
        fmt.println("Library loaded successfully.")
    } else {
        // Print the actual OS error so we know why it failed!
        fmt.println("Failed to load library:", dynlib.last_error(), "Path:", load_path)
    }
}

lib_compile :: proc(path: string, out_path_no_ext: string) -> bool {
    out_flag_buf: [64]u8
    // Odin automatically appends .so or .dll to the -out flag
    out_flag := fmt.bprintf(out_flag_buf[:], "-out:%s", out_path_no_ext)
    
    // Let's print the exact command being run
    cmd_buf: [512]u8
    cmd := fmt.bprintf(cmd_buf[:], "odin build %s -build-mode:dll %s", path, out_flag)
    fmt.println("Running command:", cmd)
    
    p, err := os.process_start({command = {"odin", "build", path, "-build-mode:dll", out_flag}})
    if err != nil {
        fmt.println("Compile error:", err)
        return false
    }
    proc_state, proc_err := os.process_wait(p)
    
    // Check if the build actually succeeded
    if proc_err != nil || proc_state.exit_code != 0 {
        fmt.println("Build failed! Exit code:", proc_state.exit_code)
        return false
    }
    
    return true
}


folder_name_last :: proc(path: string) -> string {
    clean := strings.trim_right(path, "/\\")
    if filepath.ext(clean) != "" {
        clean = filepath.dir(clean)
    }
    return filepath.base(clean)
}