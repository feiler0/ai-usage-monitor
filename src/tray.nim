## System tray integration

when defined(windows):
  import winim/lean
  import winim/inc/shellapi

const
  WM_TRAY_ICON = 0x8002
  TRAY_ID = 1
  RUN_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
  RUN_VALUE = "AIUsageMonitor"

type
  TrayIcon* = ref object
    hwnd*: HWND
    hIcon*: HICON
    visible*: bool

var gTray: TrayIcon

proc exePath(): string =
  var buf: array[MAX_PATH, WCHAR]
  let len = GetModuleFileNameW(cast[HINSTANCE](0), buf[0].addr, MAX_PATH)
  if len == 0:
    return ""
  result = $cast[WideCString](buf[0].addr)

proc runCommand(): string =
  let path = exePath()
  if path.len == 0:
    ""
  else:
    "\"" & path & "\""

proc startupEnabled*(): bool =
  var hKey: HKEY
  if RegOpenKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_READ, hKey.addr) != ERROR_SUCCESS:
    return false
  defer: RegCloseKey(hKey)

  var data: array[1024, WCHAR]
  var dataSize = DWORD(data.len * sizeof(WCHAR))
  var valueType: DWORD
  if RegQueryValueExW(hKey, RUN_VALUE, nil, valueType.addr,
      cast[LPBYTE](data[0].addr), dataSize.addr) != ERROR_SUCCESS:
    return false
  if valueType != REG_SZ:
    return false
  result = ($cast[WideCString](data[0].addr)) == runCommand()

proc setStartupEnabled*(enabled: bool): bool =
  var hKey: HKEY
  if RegCreateKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, nil, 0, KEY_SET_VALUE,
      nil, hKey.addr, nil) != ERROR_SUCCESS:
    return false
  defer: RegCloseKey(hKey)

  if enabled:
    let value = runCommand()
    if value.len == 0:
      return false
    let wide = newWideCString(value)
    result = RegSetValueExW(hKey, RUN_VALUE, 0, REG_SZ, cast[LPBYTE](wide[0].addr),
      DWORD((value.len + 1) * sizeof(WCHAR))) == ERROR_SUCCESS
  else:
    let rc = RegDeleteValueW(hKey, RUN_VALUE)
    result = rc == ERROR_SUCCESS or rc == ERROR_FILE_NOT_FOUND

proc createMonitorIcon(): HICON =
  let size = max(16, GetSystemMetrics(SM_CXSMICON))
  let hdc = GetDC(0)
  let mem = CreateCompatibleDC(hdc)
  let color = CreateCompatibleBitmap(hdc, size, size)
  let mask = CreateBitmap(size, size, 1, 1, nil)
  let oldBmp = SelectObject(mem, color)

  var rc = RECT(left: 0, top: 0, right: size, bottom: size)
  let bg = CreateSolidBrush(RGB(22, 25, 30))
  FillRect(mem, rc.addr, bg)
  DeleteObject(bg)

  let border = CreatePen(PS_SOLID, 1, RGB(78, 87, 98))
  let oldPen = SelectObject(mem, border)
  let oldBrush = SelectObject(mem, GetStockObject(HOLLOW_BRUSH))
  RoundRect(mem, 1, 1, size - 1, size - 1, 5, 5)
  SelectObject(mem, oldBrush)
  SelectObject(mem, oldPen)
  DeleteObject(border)

  let oldNullPen = SelectObject(mem, GetStockObject(NULL_PEN))
  let green = CreateSolidBrush(RGB(42, 217, 139))
  let oldGreen = SelectObject(mem, green)
  Ellipse(mem, size div 4 - 2, size div 2 - 3, size div 4 + 4, size div 2 + 3)
  SelectObject(mem, oldGreen)
  DeleteObject(green)

  let amber = CreateSolidBrush(RGB(238, 167, 74))
  let oldAmber = SelectObject(mem, amber)
  Ellipse(mem, (size * 3) div 4 - 4, size div 2 - 3, (size * 3) div 4 + 2, size div 2 + 3)
  SelectObject(mem, oldAmber)
  DeleteObject(amber)
  SelectObject(mem, oldNullPen)

  SelectObject(mem, mask)
  PatBlt(mem, 0, 0, size, size, BLACKNESS)
  SelectObject(mem, oldBmp)
  DeleteDC(mem)
  ReleaseDC(0, hdc)

  var info: ICONINFO
  info.fIcon = TRUE
  info.hbmColor = color
  info.hbmMask = mask
  result = CreateIconIndirect(info.addr)
  DeleteObject(color)
  DeleteObject(mask)

proc fillTip(nid: var NOTIFYICONDATAW) =
  let tip = "AI Usage Monitor"
  for i in 0..<min(tip.len, 127):
    nid.szTip[i] = cast[WCHAR](tip[i])
  nid.szTip[min(tip.len, 127)] = cast[WCHAR](0)

proc createTrayIcon*(hwnd: HWND): bool =
  var nid: NOTIFYICONDATAW
  nid.cbSize = cast[DWORD](sizeof(NOTIFYICONDATAW))
  nid.hWnd = hwnd
  nid.uID = TRAY_ID
  nid.uFlags = cast[UINT](NIF_MESSAGE or NIF_ICON or NIF_TIP)
  nid.uCallbackMessage = WM_TRAY_ICON
  nid.hIcon = createMonitorIcon()
  if nid.hIcon == 0:
    nid.hIcon = LoadIconW(cast[HINSTANCE](0), IDI_APPLICATION)
  fillTip(nid)

  result = Shell_NotifyIconW(NIM_ADD, nid.addr) != 0
  if result:
    gTray = TrayIcon(hwnd: hwnd, hIcon: nid.hIcon, visible: true)
  elif nid.hIcon != 0:
    DestroyIcon(nid.hIcon)

proc showTrayMenu*(hwnd: HWND) =
  let hMenu = CreatePopupMenu()
  AppendMenuW(hMenu, MF_STRING, cast[UINT_PTR](1), "显示/隐藏")
  let startupFlag = cast[UINT](if startupEnabled(): MF_STRING or MF_CHECKED else: MF_STRING)
  AppendMenuW(hMenu, startupFlag, cast[UINT_PTR](2), "开机自启动")
  AppendMenuW(hMenu, MF_SEPARATOR, 0, nil)
  AppendMenuW(hMenu, MF_STRING, cast[UINT_PTR](3), "退出")

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
    discard setStartupEnabled(not startupEnabled())
  of 3:
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
    if gTray.hIcon != 0:
      DestroyIcon(gTray.hIcon)
    gTray = nil

proc restoreWindow*(hwnd: HWND) =
  ShowWindow(hwnd, SW_SHOW)
  SetForegroundWindow(hwnd)
