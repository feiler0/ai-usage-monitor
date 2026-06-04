## 系统托盘模块

when defined(windows):
  import winim/lean
  import winim/inc/shellapi

const
  WM_TRAY_ICON = 0x8002
  TRAY_ID = 1

type
  TrayIcon* = ref object
    hwnd*: HWND
    visible*: bool

var gTray: TrayIcon

proc createTrayIcon*(hwnd: HWND): bool =
  var nid: NOTIFYICONDATAW
  nid.cbSize = cast[DWORD](sizeof(NOTIFYICONDATAW))
  nid.hWnd = hwnd
  nid.uID = TRAY_ID
  nid.uFlags = cast[UINT](NIF_MESSAGE or NIF_ICON or NIF_TIP)
  nid.uCallbackMessage = WM_TRAY_ICON
  nid.hIcon = LoadIconW(cast[HINSTANCE](0), IDI_APPLICATION)
  let tip = "AI Usage Monitor"
  for i in 0..<min(tip.len, 127):
    nid.szTip[i] = cast[WCHAR](tip[i])
  nid.szTip[min(tip.len, 127)] = cast[WCHAR](0)
  result = Shell_NotifyIconW(NIM_ADD, nid.addr) != 0
  if result:
    gTray = TrayIcon(hwnd: hwnd, visible: true)

proc showTrayMenu*(hwnd: HWND) =
  let hMenu = CreatePopupMenu()
  AppendMenuW(hMenu, MF_STRING, cast[UINT_PTR](1), "显示/隐藏")
  AppendMenuW(hMenu, MF_SEPARATOR, 0, nil)
  AppendMenuW(hMenu, MF_STRING, cast[UINT_PTR](2), "退出")

  SetForegroundWindow(hwnd)
  var pt: POINT
  GetCursorPos(pt.addr)

  let cmd = TrackPopupMenu(hMenu, TPM_RETURNCMD or TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nil)
  DestroyMenu(hMenu)

  case cmd
  of 1:
    if IsWindowVisible(hwnd) != 0:
      ShowWindow(hwnd, SW_HIDE)
    else:
      ShowWindow(hwnd, SW_SHOW)
  of 2:
    DestroyWindow(hwnd)
  else:
    discard

proc removeTrayIcon*() =
  if gTray != nil:
    var nid: NOTIFYICONDATAW
    nid.cbSize = cast[DWORD](sizeof(NOTIFYICONDATAW))
    nid.hWnd = gTray.hwnd
    nid.uID = TRAY_ID
    discard Shell_NotifyIconW(NIM_DELETE, nid.addr)

proc restoreWindow*(hwnd: HWND) =
  ShowWindow(hwnd, SW_SHOW)
  SetForegroundWindow(hwnd)
