## Win32 进程存在性检查

when defined(windows):
  import std/strutils
  import winim/lean
  import winim/inc/tlhelp32

  proc exeName(entry: PROCESSENTRY32W): string =
    result = $cast[WideCString](unsafeAddr entry.szExeFile[0])

  proc processNameExists*(name: string): bool =
    let wanted = name.toLowerAscii()
    let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == INVALID_HANDLE_VALUE:
      return false
    defer: CloseHandle(snapshot)

    var entry: PROCESSENTRY32W
    entry.dwSize = DWORD(sizeof(PROCESSENTRY32W))
    if Process32FirstW(snapshot, entry.addr) == 0:
      return false
    while true:
      if exeName(entry).toLowerAscii() == wanted:
        return true
      if Process32NextW(snapshot, entry.addr) == 0:
        break

else:
  proc processNameExists*(name: string): bool = false
