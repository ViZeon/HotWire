package watcher

import "core:strings"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sys/linux"
import "core:sys/windows"

Action :: enum {
	Modified,
	Created,
	Deleted,
	RenamedFrom,
	RenamedTo,
}


hot_reload :: proc(path: string, file_updated: ^bool) {
	lib_update(path)
    platform_watch_dir(path, file_updated)
    
}

lib_path_update :: proc(path, lib_name: string) {
	// If watch_path is "./src/reloadable" and lib_name is "lib.so"
	//full_path, err := filepath.join({path, lib_name, lib_extension()}, context.allocator)
	// Result: "./src/reloadable/lib.so"
}

lib_update :: proc(/*lib_counter: ^int,*/ path: string) {


    // Get the directory containing the file
    dir := filepath.dir(path)           // "/home/user/projects/myapp/src"

    // Get the last folder name
    lib_name:= filepath.base(path)    // "src"
    ext:= lib_extension()
    lib_name = strings.concatenate({lib_name,ext})
	// Linux: load a copy so the build can overwrite lib.so

    //clean_path, err2 := filepath.clean(path, context.allocator)
    full_path, err := filepath.join({path, lib_name }, context.allocator)
	//tmp := fmt.tprintf(path, lib_counter)
	//lib_counter^ += 1

	//os.copy_file("source.so", "dest.so")
    fmt.println(dir)
    fmt.println(lib_name)
    fmt.println(lib_extension())
	fmt.println("library written successfully.", full_path)

}


lib_compile :: proc() {
	//compile_command := fmt.tprintf("odin build hotcode/%v.odin -build-mode:dll -out:hotcode/%v -file", hl.name, hl.dirs[hl.idx])
}
// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
