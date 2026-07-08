package hot_reload

import "core:sys/windows"

when ODIN_OS == .Windows {
    Handle :: windows.HANDLE

    events_os_open :: proc(path: string) -> Handle {
        return windows.CreateFileA(
            raw_data(path), windows.FILE_LIST_DIRECTORY,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            nil, windows.OPEN_EXISTING, windows.FILE_FLAG_BACKUP_SEMANTICS, nil,
        )
    }

    events_os_track :: proc(handle: Handle, buffer: []u8) -> int {
        bytes_returned: u32
        windows.ReadDirectoryChangesW(
            handle, raw_data(buffer), u32(len(buffer)), false,
            windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME,
            &bytes_returned, nil, nil,
        )
        return int(bytes_returned)
    }

    events_os_cast :: proc(buffer: []u8, offset: int) -> (Action, int) {
        info := cast(^windows.FILE_NOTIFY_INFORMATION)&buffer[offset]

        action: Action
        switch info.Action {
        case windows.FILE_ACTION_ADDED:            action = .Created
        case windows.FILE_ACTION_REMOVED:          action = .Deleted
        case windows.FILE_ACTION_MODIFIED:         action = .Modified
        case windows.FILE_ACTION_RENAMED_OLD_NAME: action = .RenamedFrom
        case windows.FILE_ACTION_RENAMED_NEW_NAME: action = .RenamedTo
        }

        next_offset := offset
        if info.NextEntryOffset != 0 do next_offset = offset + int(info.NextEntryOffset)
        return action, next_offset
    }

    lib_extension :: proc() -> string { return ".dll" }
}