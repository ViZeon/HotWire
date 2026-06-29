package watcher

import "core:os"
import "core:sys/linux"
import "core:sys/windows"
import "core:path/filepath"

Action :: enum {
    Modified,
    Created,
    Deleted,
    RenamedFrom,
    RenamedTo,
}



hot_reload :: proc(path: cstring, file_updated: ^bool) {
    watch_dir(path, file_updated)
}

lib_path_update :: proc (path, lib_name: string) {
    // If watch_path is "./src/reloadable" and lib_name is "lib.so"
    full_path, err := filepath.join({path, lib_name}, context.allocator)
    // Result: "./src/reloadable/lib.so"
}



// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
