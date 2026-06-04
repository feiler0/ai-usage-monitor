## AI Usage Monitor — 主入口

import models, config, storage, monitor, ui, tray
import sources/codex

when defined(windows):
  import winim/lean

proc messageLoop(hwnd: HWND): void =
  var msg: MSG
  while GetMessageW(msg.addr, 0, 0, 0) != 0:
    TranslateMessage(msg.addr)
    DispatchMessageW(msg.addr)

proc WinMain(hInstance: HINSTANCE, hPrevInstance: HINSTANCE, lpCmdLine: LPWSTR, nCmdShow: int32): int32 {.stdcall.} =
  var cfg = loadConfig()
  if cfg.codexSessionDir.len == 0:
    cfg.codexSessionDir = getCodexSessionsRoot()

  var stats = loadStats()
  var mon = initMonitor(cfg, stats)
  refreshAll(mon)

  let hwnd = createWindow(mon)
  discard createTrayIcon(hwnd)
  messageLoop(hwnd)

  removeTrayIcon()
  saveCurrentWindowPosition(hwnd)
  saveConfig(mon.config)
  saveStats(mon.stats)
  closeMonitor(mon)
  return 0

when isMainModule:
  when defined(windows):
    var hInstance = cast[HINSTANCE](GetModuleHandleW(nil))
    var nCmdShow: int32 = SW_SHOWNORMAL
    var cmdLine = GetCommandLineW()
    discard WinMain(hInstance, cast[HINSTANCE](0), cmdLine, nCmdShow)
  else:
    echo "This application only runs on Windows."
