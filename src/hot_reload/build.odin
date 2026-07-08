package hot_reload

import "core:fmt"
import "core:log"
import "core:os"

// TODO(custom-build): make this configurable once the API grows
// past one line.
OUT_DIR :: ".hotreload"

// Derives the .so/.dll path for a watched directory. Computed fresh
// from `path` every time -- never cached.
lib_path :: proc(path: string) -> string {
	return fmt.tprintf("%s/%s%s", OUT_DIR, folder_name_last(path), lib_extension())
}

// Compiles `path` directly via `odin build`. Sole compile step.
// TODO(custom-build): allow a caller-supplied command/args instead
// of this hardcoded invocation.
build :: proc(path: string) -> bool {
	os.make_directory(OUT_DIR) // fine if it already exists

	cmd := []string{
		"odin", "build", path,
		"-build-mode:dll",
		fmt.tprintf("-out:%s", lib_path(path)),
	}

	p, start_err := os.process_start({command = cmd})
	if start_err != nil {
		log.error("hot_reload: failed to start build:", start_err)
		return false
	}

	result, wait_err := os.process_wait(p)
	if wait_err != nil {
		log.error("hot_reload: build process error:", wait_err)
		return false
	}

	return result.success
}
