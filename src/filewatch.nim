## 单线程目录变化监听

import std/os

when defined(windows):
  import winim/lean

  type
    DirectoryWatcher* = object
      path*: string
      handle*: HANDLE
      eventHandle*: HANDLE
      overlapped*: OVERLAPPED
      buffer*: array[8192, byte]
      pending*: bool
      recursive*: bool

  const
    WatchFilter = FILE_NOTIFY_CHANGE_FILE_NAME or
      FILE_NOTIFY_CHANGE_DIR_NAME or
      FILE_NOTIFY_CHANGE_LAST_WRITE or
      FILE_NOTIFY_CHANGE_SIZE

  proc close*(w: var DirectoryWatcher) =
    if w.handle != 0 and w.handle != INVALID_HANDLE_VALUE:
      discard CancelIo(w.handle)
      CloseHandle(w.handle)
    if w.eventHandle != 0:
      CloseHandle(w.eventHandle)
    w.handle = 0
    w.eventHandle = 0
    w.pending = false

  proc queue(w: var DirectoryWatcher): bool =
    if w.handle == 0 or w.handle == INVALID_HANDLE_VALUE or w.eventHandle == 0:
      return false
    ResetEvent(w.eventHandle)
    zeroMem(w.overlapped.addr, sizeof(OVERLAPPED))
    w.overlapped.hEvent = w.eventHandle
    var bytesReturned: DWORD = 0
    let ok = ReadDirectoryChangesW(
      w.handle,
      w.buffer.addr,
      DWORD(w.buffer.len),
      if w.recursive: TRUE else: FALSE,
      WatchFilter,
      bytesReturned.addr,
      w.overlapped.addr,
      nil
    )
    w.pending = ok != 0
    result = w.pending

  proc initDirectoryWatcher*(path: string, recursive: bool = true): DirectoryWatcher =
    result.path = path
    result.recursive = recursive
    result.handle = INVALID_HANDLE_VALUE
    if not dirExists(path):
      return

    result.eventHandle = CreateEventW(nil, TRUE, FALSE, nil)
    result.handle = CreateFileW(
      path,
      FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
      0
    )

    if result.handle == INVALID_HANDLE_VALUE or result.eventHandle == 0:
      close(result)
      return
    discard queue(result)

  proc changed*(w: var DirectoryWatcher): bool =
    if not w.pending:
      discard queue(w)
      return false
    if WaitForSingleObject(w.eventHandle, 0) != WAIT_OBJECT_0:
      return false

    var transferred: DWORD = 0
    discard GetOverlappedResult(w.handle, w.overlapped.addr, transferred.addr, FALSE)
    w.pending = false
    discard queue(w)
    result = true

else:
  type
    DirectoryWatcher* = object
      path*: string

  proc initDirectoryWatcher*(path: string, recursive: bool = true): DirectoryWatcher =
    result.path = path

  proc changed*(w: var DirectoryWatcher): bool = false
  proc close*(w: var DirectoryWatcher) = discard
