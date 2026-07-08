package hot_reload

import "core:strings"
import "core:sys/linux"

when ODIN_OS == .Linux {
    Handle :: linux.Fd

    IN_MODIFY     :: 0x00000002
    IN_CREATE     :: 0x00000100
    IN_DELETE     :: 0x00000200
    IN_MOVED_FROM :: 0x00000040
    IN_MOVED_TO   :: 0x00000080

    events_os_open :: proc(path: string) -> Handle {
        fd, _ := linux.inotify_init()
        mask := transmute(bit_set[linux.Inotify_Event_Bits;u32])(u32(
                IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO,
            ))
        linux.inotify_add_watch(fd, strings.clone_to_cstring(path), mask)
        return fd
    }

    events_os_track :: proc(handle: Handle, buffer: []u8) -> int {
        n, _ := linux.read(handle, buffer)
        return int(n)
    }

    // Now returns the filename as well
    events_os_cast :: proc(buffer: []u8, offset: int) -> (Action, string, int) {
        event := cast(^linux.Inotify_Event)&buffer[offset]
        mask := u32(transmute(u32)event.mask)

        action: Action
        switch {
        case (mask & IN_MODIFY) != 0:     action = .Modified
        case (mask & IN_CREATE) != 0:     action = .Created
        case (mask & IN_DELETE) != 0:     action = .Deleted
        case (mask & IN_MOVED_FROM) != 0: action = .RenamedFrom
        case (mask & IN_MOVED_TO) != 0:   action = .RenamedTo
        }

        name: string
        if event.len > 0 {
            name = string(cstring(&buffer[offset + size_of(linux.Inotify_Event)]))
        }

        next_offset := offset + size_of(linux.Inotify_Event) + int(event.len)
        return action, name, next_offset
    }

    lib_extension :: proc() -> string { return ".so" }
}