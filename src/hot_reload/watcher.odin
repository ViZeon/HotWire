package hot_reload

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


watch :: proc(path: string, file_updated: ^bool) {
	lib_update(path)
	platform_watch_dir(path, file_updated)

}
watch_list :: proc() {

}

lib_path_update :: proc(path, lib_name: string) {
	// If watch_path is "./src/reloadable" and lib_name is "lib.so"
	//full_path, err := filepath.join({path, lib_name, lib_extension()}, context.allocator)
	// Result: "./src/reloadable/lib.so"
}

lib_update :: proc(
	 /*lib_counter: ^int,*/path: string,
) {

	// Get the last folder name
	lib_name := folder_name_last(path) //filepath.base(path)    // "src"
	ext := lib_extension()
	lib_name = strings.concatenate({lib_name, ext})
	// Linux: load a copy so the build can overwrite lib.so

	//clean_path, err2 := filepath.clean(path, context.allocator)
	full_path, err := filepath.join({path, lib_name}, context.allocator)
	//tmp := fmt.tprintf(path, lib_counter)
	//lib_counter^ += 1

	//os.copy_file("source.so", "dest.so")

	fmt.println(lib_name)
	fmt.println(lib_extension())
	fmt.println("Path read successfully.", full_path)

}


lib_compile :: proc() {
	//compile_command := fmt.tprintf("odin build hotcode/%v.odin -build-mode:dll -out:hotcode/%v -file", hl.name, hl.dirs[hl.idx])
	// replace that with the path you retrieve from the other func
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
