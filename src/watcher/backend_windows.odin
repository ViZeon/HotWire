
package watcher

import "core:fmt"
import "core:os"
import "core:sys/windows"

// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
// watcher_windows.odin

when ODIN_OS == .Windows {
    watch_dir :: proc(path: string) {
        dir_handle := windows.CreateFileA(
            raw_data(path),
            windows.FILE_LIST_DIRECTORY,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            nil,
            windows.OPEN_EXISTING,
            windows.FILE_FLAG_BACKUP_SEMANTICS,
            nil,
        )

        buffer: [1024]u32
        bytes_returned: u32

        for {
            windows.ReadDirectoryChangesW(
                dir_handle,
                &buffer[0],
                u32(len(buffer) * size_of(u32)),
                false,
                windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME,
                &bytes_returned,
                nil,
                nil,
            )

            if bytes_returned <= 0 do continue

            offset: u32 = 0
            for {
                raw_ptr := cast(^u8)&buffer[0]
                info := cast(^windows.FILE_NOTIFY_INFORMATION)&raw_ptr[offset]

                action: Action
                switch info.Action {
                case windows.FILE_ACTION_ADDED:             action = .Created
                case windows.FILE_ACTION_REMOVED:           action = .Deleted
                case windows.FILE_ACTION_MODIFIED:          action = .Modified
                case windows.FILE_ACTION_RENAMED_OLD_NAME:  action = .RenamedFrom
                case windows.FILE_ACTION_RENAMED_NEW_NAME:  action = .RenamedTo
                    // Treat renames as modifications or ignore; here we skip
                    continue
                }

               // FileNameLength is in bytes. Divide by 2 to get the number of WCHARs (UTF-16 characters)
                name_len_chars := info.FileNameLength / 2

                fmt.printf("[%s] ", action)
                // Print the UTF-16 characters one by one
                for i in 0 ..< name_len_chars {
                    fmt.printf("%r", rune(info.FileName[i]))
                }
                fmt.println()

                // Move to the next event, or break if this is the last one
                if info.NextEntryOffset == 0 do break
                offset += info.NextEntryOffset
            }
        }
    }
}