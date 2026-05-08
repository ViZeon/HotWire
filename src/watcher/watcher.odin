package watcher

import "core:os"
import "core:sys/linux"
import "core:sys/windows"

// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
