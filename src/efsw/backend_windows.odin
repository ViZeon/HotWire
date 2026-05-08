package efsw

import "core:sys/windows"
import "core:strings"
import "core:unicode/utf16"
import "core:mem"

when ODIN_OS == .Windows {

FILE_NOTIFY_CHANGE_FILE_NAME  :: u32(0x00000001)
FILE_NOTIFY_CHANGE_DIR_NAME   :: u32(0x00000002)
FILE_NOTIFY_CHANGE_ATTRIBUTES :: u32(0x00000004)
FILE_NOTIFY_CHANGE_SIZE       :: u32(0x00000008)
FILE_NOTIFY_CHANGE_LAST_WRITE :: u32(0x00000010)
FILE_NOTIFY_CHANGE_CREATION   :: u32(0x00000040)

FILE_ACTION_ADDED            :: u32(0x00000001)
FILE_ACTION_REMOVED          :: u32(0x00000002)
FILE_ACTION_MODIFIED         :: u32(0x00000003)
FILE_ACTION_RENAMED_OLD_NAME :: u32(0x00000004)
FILE_ACTION_RENAMED_NEW_NAME :: u32(0x00000005)

FILE_LIST_DIRECTORY        :: u32(0x0001)
FILE_SHARE_READ            :: u32(0x00000001)
FILE_SHARE_WRITE           :: u32(0x00000002)
FILE_SHARE_DELETE          :: u32(0x00000004)
OPEN_EXISTING              :: u32(3)
FILE_FLAG_BACKUP_SEMANTICS :: u32(0x02000000)

FILE_NOTIFY_INFORMATION :: struct #packed {
	NextEntryOffset: u32,
	Action:          u32,
	FileNameLength:  u32,
	FileName:        [1]u16,
}

_windows_watcher :: struct {
	handle:     windows.HANDLE,
	dir:        string,
	rename_old: string,
	has_rename: bool,
}

_init_windows :: proc(w: ^Watcher) -> rawptr {
	ww := new(_windows_watcher, w.allocator)
	ww.handle = windows.INVALID_HANDLE_VALUE
	ww.dir = ""
	ww.has_rename = false
	return rawptr(ww)
}

_add_watch_windows :: proc(w: ^Watcher, path: string) -> bool {
	ww := (^_windows_watcher)(w.impl)
	if ww.handle != windows.INVALID_HANDLE_VALUE {
		return false // barebones: one watch per watcher
	}

	ww.dir = strings.clone(path, w.allocator)
	wpath := utf16.encode_string(path, context.temp_allocator)

	handle := windows.CreateFileW(
		raw_data(wpath),
		FILE_LIST_DIRECTORY,
		FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
		nil,
		OPEN_EXISTING,
		FILE_FLAG_BACKUP_SEMANTICS,
		nil,
	)
	if handle == windows.INVALID_HANDLE_VALUE {
		delete(ww.dir, w.allocator)
		ww.dir = ""
		return false
	}
	ww.handle = handle
	return true
}

_remove_watch_windows :: proc(w: ^Watcher, path: string) -> bool {
	ww := (^_windows_watcher)(w.impl)
	if ww.dir == path && ww.handle != windows.INVALID_HANDLE_VALUE {
		windows.CloseHandle(ww.handle)
		ww.handle = windows.INVALID_HANDLE_VALUE
		delete(ww.dir, w.allocator)
		ww.dir = ""
		return true
	}
	return false
}

_stop_windows :: proc(w: ^Watcher) {
	ww := (^_windows_watcher)(w.impl)
	if ww.handle != windows.INVALID_HANDLE_VALUE {
		windows.CloseHandle(ww.handle)
		ww.handle = windows.INVALID_HANDLE_VALUE
	}
}

_run_windows :: proc(w: ^Watcher) {
	ww := (^_windows_watcher)(w.impl)
	buf: [4096]u8
	bytes_returned: u32

	for {
		if ww.handle == windows.INVALID_HANDLE_VALUE {
			break
		}

		ok := windows.ReadDirectoryChangesW(
			ww.handle,
			&buf[0],
			u32(len(buf)),
			true, // recursive
			FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME |
			FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_SIZE |
			FILE_NOTIFY_CHANGE_ATTRIBUTES | FILE_NOTIFY_CHANGE_CREATION,
			&bytes_returned,
			nil,
			nil,
		)
		if !ok {
			break
		}

		offset := 0
		for {
			info := (^FILE_NOTIFY_INFORMATION)(&buf[offset])

			name_len := int(info.FileNameLength) / size_of(u16)
			name_utf16 := mem.slice_ptr(&info.FileName[0], name_len)
			name := utf16.decode_to_utf8(name_utf16, w.allocator)

			switch info.Action {
			case FILE_ACTION_ADDED:
				w.callback(Event{dir = ww.dir, file = name, type = .Created})
			case FILE_ACTION_REMOVED:
				w.callback(Event{dir = ww.dir, file = name, type = .Deleted})
			case FILE_ACTION_MODIFIED:
				w.callback(Event{dir = ww.dir, file = name, type = .Modified})
			case FILE_ACTION_RENAMED_OLD_NAME:
				ww.rename_old = name
				ww.has_rename = true
			case FILE_ACTION_RENAMED_NEW_NAME:
				if ww.has_rename {
					w.callback(Event{
						dir      = ww.dir,
						file     = name,
						type     = .Moved,
						old_file = ww.rename_old,
					})
					delete(ww.rename_old, w.allocator)
					ww.has_rename = false
				} else {
					w.callback(Event{dir = ww.dir, file = name, type = .Created})
				}
			}

			if info.Action != FILE_ACTION_RENAMED_OLD_NAME {
				delete(name, w.allocator)
			}

			if info.NextEntryOffset == 0 {
				break
			}
			offset += int(info.NextEntryOffset)
		}
	}
}

_destroy_windows :: proc(w: ^Watcher) {
	ww := (^_windows_watcher)(w.impl)
	if ww == nil { return }

	if ww.handle != windows.INVALID_HANDLE_VALUE {
		windows.CloseHandle(ww.handle)
	}
	if ww.dir != "" {
		delete(ww.dir, w.allocator)
	}
	if ww.has_rename {
		delete(ww.rename_old, w.allocator)
	}
	free(ww, w.allocator)
}

}