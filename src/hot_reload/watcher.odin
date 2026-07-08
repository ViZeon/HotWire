package hot_reload

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/linux"
import "core:sys/windows"

Action :: enum {
    Modified,
    Created,
    Deleted,
    RenamedFrom,
    RenamedTo,
}


old_watch :: proc(path: string, file_updated: ^bool) {
    lib_update(path)
    //platform_watch_dir(path, file_updated)

}

watch :: proc(path: string, file_updated: ^bool) {
    handle := events_os_open(path)
    buffer: [4096]u8

    for {
        n := events_os_track(handle, buffer[:])
        if n <= 0 do continue

        offset := 0
        for offset < n {
            action, next_offset := events_os_cast(buffer[:], offset)
            if next_offset == offset do break // Windows sentinel: no more records
            offset = next_offset
            file_updated^ = true
        }
    }
}

lib_path_update :: proc(path, lib_name: string) -> string {
    // If watch_path is "./src/reloadable" and lib_name is "lib.so"
    full_path, err := filepath.join({path, lib_name}, context.allocator)
    if err != nil {
        fmt.println("Path join error:", err)
        return ""
    }
    // Result: "./src/reloadable/lib.so"
    return full_path
}

lib_update :: proc(
     /*lib_counter: ^int,*/path: string,
     lib_handle: ^dynlib.Library = nil, // Optional pointer so library can handle loading statelessly
) {

    // Get the last folder name
    lib_name := folder_name_last(path) //filepath.base(path)    // "src"
    ext := lib_extension()
    lib_name = strings.concatenate({lib_name, ext})
    
    full_path := lib_path_update(path, lib_name)

    // 1. Compile
    lib_compile(path, full_path)

    // 2. Unload old handle if it exists
    if lib_handle != nil && lib_handle^ != nil {
        dynlib.unload_library(lib_handle^)
        lib_handle^ = nil
    }

    // 3. Load the newly built library
    if lib_handle != nil {
        load_path := full_path
        
        // Handle Linux .so overwrite issue statelessly using cross-platform extension check
        if ext == ".so" {
            temp_path := fmt.tprintf("%s_loaded%s", strings.trim_suffix(full_path, ext), ext)
            err_copy:= os.copy_file(full_path, temp_path)
            load_path = temp_path
        }

        handle, ok := dynlib.load_library(load_path)
        if ok do lib_handle^ = handle
    }

    fmt.println(lib_name)
    fmt.println(lib_extension())
    fmt.println("Path read successfully.", full_path)
}

lib_compile :: proc(path: string, full_path: string) {
    // Cross-platform process start: directly invoke the odin compiler without shell wrappers
    out_flag := fmt.tprintf("-out:%s", full_path)
    p, err := os.process_start({command = {"odin", "build", path, "-build-mode:dll", out_flag}})
    if err != nil {
        fmt.println("Compile error:", err)
        return
    }
    state, err_terminal:= os.process_wait(p)
}
// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)


folder_name_last :: proc(path: string) -> string {
    // Strip trailing slashes so base() works correctly
    clean := strings.trim_right(path, "/\\")

    // If path ends with a filename (has extension), go up one level
    if filepath.ext(clean) != "" {
        clean = filepath.dir(clean)
    }

    return filepath.base(clean)
}