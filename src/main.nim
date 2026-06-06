## AI Usage Monitor — 主入口

import models, config, storage, monitor, ui, tray, memoryutil
import sources/codex

when defined(windows):
  import winim/lean

const
  SINGLE_INSTANCE_MUTEX = "Local\\AIUsageMonitor.SingleInstance"

proc acquireSingleInstance(): HANDLE =
  let name = newWideCString(SINGLE_INSTANCE_MUTEX)
  result = CreateMutexW(nil, TRUE, name)
  if result == 0:
    return 0
  if GetLastError() == ERROR_ALREADY_EXISTS:
    CloseHandle(result)
    return 0

proc messageLoop(hwnd: HWND): void =
  var msg: MSG
  while GetMessageW(msg.addr, 0, 0, 0) != 0:
    TranslateMessage(msg.addr)
    DispatchMessageW(msg.addr)

proc WinMain(hInstance: HINSTANCE, hPrevInstance: HINSTANCE, lpCmdLine: LPWSTR, nCmdShow: int32): int32 {.stdcall.} =
  let singleInstance = acquireSingleInstance()
  if singleInstance == 0:
    return 0

  var cfg = loadConfig()
  if cfg.codexSessionDir.len == 0:
    cfg.codexSessionDir = getCodexSessionsRoot()

  var stats = loadStats()
  var mon = initMonitor(cfg, stats)
  refreshAll(mon)

  let hwnd = createWindow(mon)
  discard createTrayIcon(hwnd)
  trimWorkingSet()
  messageLoop(hwnd)

  removeTrayIcon()
  saveCurrentWindowPosition(hwnd)
  saveConfig(mon.config)
  saveStats(mon.stats)
  closeMonitor(mon)
  CloseHandle(singleInstance)
  return 0

when isMainModule:
  when defined(windows):
    var hInstance = cast[HINSTANCE](GetModuleHandleW(nil))
    var nCmdShow: int32 = SW_SHOWNORMAL
    var cmdLine = GetCommandLineW()
    discard WinMain(hInstance, cast[HINSTANCE](0), cmdLine, nCmdShow)
  else:
    echo "This application only runs on Windows."
