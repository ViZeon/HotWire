
package watcher

import "core:os"
import "core:sys/windows"

// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
 when ODIN_OS == .Windows {
    watch_directory :: proc(dir_path: cstring, callback: proc(action: string, file: string)) {
   dir_handle := windows.CreateFileA(
            raw_data(dir_path), windows.FILE_LIST_DIRECTORY,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            nil, windows.OPEN_EXISTING, windows.FILE_FLAG_BACKUP_SEMANTICS, nil,
        )
        buf: [1024]u32
        bytes_returned: u32
        for {
            windows.ReadDirectoryChangesW(dir_handle, &buf[0], u32(len(buf)*size_of(u32)), false,
                windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME,
                &bytes_returned, nil, nil)
            if bytes_returned > 0 {
                offset: u32 = 0
                for {
                    raw := cast(^u8)&buf[0]
                    info := cast(^windows.FILE_NOTIFY_INFORMATION)&raw[offset]
                    act := "Modified" if info.Action == windows.FILE_ACTION_MODIFIED else "Created" if info.Action == windows.FILE_ACTION_ADDED else "Deleted"
                    name_bytes := make([]byte, info.FileNameLength/2) // UTF-16 → ASCII (assumes ASCII)
                    for i := 0; i < int(info.FileNameLength/2); i += 1 {
                        name_bytes[i] = byte(info.FileName[i])
                    }
                    callback(act, string(name_bytes))
                    if info.NextEntryOffset == 0 do break
                    offset += info.NextEntryOffset
                }
            }
        }
    }

}