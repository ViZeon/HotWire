
package watcher

import "core:os"
import "core:sys/linux"
import "core:sys/windows"

// Callback receives: action "Modified", "Created", "Deleted" and file name (just the name, not full path)
 when ODIN_OS == .Linux {
    watch_directory :: proc(dir_path: cstring, callback: proc(action: string, file: string)) {
   
        fd, _ := linux.inotify_init()
        linux.inotify_add_watch(fd, dir_path, transmute(bit_set[linux.Inotify_Event_Bits;u32])u32(0x00000002 | 0x00000100 | 0x00000200))
        buf: [1024]u8
        for {
            n, _ := linux.read(fd, buf[:])
            offset: u32 = 0
            for offset < u32(n) {
                ev := cast(^linux.Inotify_Event)&buf[offset]
                mask := u32(transmute(u32)ev.mask)
                act := "Modified" if mask & 0x02 != 0 else "Created" if mask & 0x100 != 0 else "Deleted"
                if ev.len > 0 {
                    name := string(cast(cstring)&buf[offset + size_of(linux.Inotify_Event)])
                    callback(act, name)
                }
                offset += size_of(linux.Inotify_Event) + ev.len
            }
        }
    }
}