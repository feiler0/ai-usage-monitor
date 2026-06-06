## UI 模块 — Win32 GDI 双缓冲绘制
## 无边框、始终置顶、可拖动、透明度可调

import std/[os, strutils, hashes]
import models
import monitor
import config
import filewatch
import tray
import sources/deepseek

when defined(windows):
  import winim/lean
  import winim/inc/shellapi

const
  WINDOW_CLASS = "AIUsageMonitor"
  WINDOW_TITLE = "AI Usage Monitor"
  WM_REFRESH_DATA = 0x8001
  WM_TRAY_ICON = 0x8002

  # 尺寸常量
  WIN_WIDTH = 260
  WIN_HEIGHT = 476
  COMPACT_WIDTH = 390
  COMPACT_HEIGHT = 38
  PADDING = 14
  ROW_HEIGHT = 19
  HEADER_HEIGHT = 25
  SECTION_GAP = 6
  # 颜色定义
  COLOR_BG_TOP = RGB(36, 39, 44)
  COLOR_BG_BOTTOM = RGB(16, 18, 22)
  COLOR_BORDER = RGB(64, 70, 78)
  COLOR_HIGHLIGHT = RGB(105, 114, 124)
  COLOR_TEXT = RGB(197, 202, 209)
  COLOR_TEXT_BRIGHT = RGB(255, 255, 255)
  COLOR_VALUE = RGB(235, 242, 246)
  COLOR_GREEN = RGB(42, 217, 139)
  COLOR_CODEX = RGB(238, 167, 74)
  COLOR_DEEPSEEK = RGB(101, 93, 255)
  COLOR_GRAY = RGB(111, 118, 128)
  COLOR_SEPARATOR = RGB(52, 58, 66)

type
  UiMode = enum
    umFull, umCompact

  UiContext* = ref object
    hwnd*: HWND
    hFont*: HFONT
    hFontMono*: HFONT
    hFontHeader*: HFONT
    hFontTiny*: HFONT
    monitor*: Monitor
    mode*: UiMode
    draggingCompact*: bool
    dragOffsetX*: int32
    configWatcher*: DirectoryWatcher
    animationFrame*: int
    lastClaudeHash*: int
    lastCodexHash*: int
    lastDeepSeekHash*: int

# 全局 UI 上下文
var gUi: UiContext

proc createFont(name: string, size: int32, bold: bool = false): HFONT =
  let weight: int32 = if bold: FW_BOLD else: FW_NORMAL
  result = CreateFontW(
    size, 0, 0, 0, weight,
    cast[DWORD](0), cast[DWORD](0), cast[DWORD](0), DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, name
  )

proc initGdi(): void =
  gUi.hFont = createFont("Microsoft YaHei UI", 19, false)
  gUi.hFontMono = createFont("Cascadia Mono", 19, false)
  gUi.hFontHeader = createFont("Microsoft YaHei UI", 21, true)
  gUi.hFontTiny = createFont("Cascadia Mono", 12, false)
proc cleanupGdi() =
  if gUi.hFont != 0: DeleteObject(gUi.hFont)
  if gUi.hFontMono != 0: DeleteObject(gUi.hFontMono)
  if gUi.hFontHeader != 0: DeleteObject(gUi.hFontHeader)
  if gUi.hFontTiny != 0: DeleteObject(gUi.hFontTiny)

proc dataHash(data: MonitorData): int =
  ## 计算数据简单哈希，用于判断是否需要重绘
  var h: Hash = 0
  h = h !& hash(data.status.int)
  h = h !& hash(data.sessionDurationSec)
  h = h !& hash(data.sessionTokens)
  h = h !& hash(data.sessionCacheTokens)
  h = h !& hash(data.todayTokens)
  h = h !& hash(data.todayCacheTokens)
  h = h !& hash(data.answering)
  result = cast[int](h)

proc deepSeekHash(data: DeepSeekData): int =
  var h: Hash = 0
  h = h !& hash(int(data.todayCost * 10000))
  h = h !& hash(data.todayTokens)
  h = h !& hash(int(data.cacheHitRate * 100))
  h = h !& hash(int(data.balance * 100))
  h = h !& hash(data.balanceCurrency)
  h = h !& hash(data.balanceAvailable)
  h = h !& hash(data.balanceOk)
  h = h !& hash(data.billUpdatedMs)
  h = h !& hash(data.sessionUpdatedMs)
  h = h !& hash(data.billStale)
  for value in data.weekTokens:
    h = h !& hash(value)
  result = cast[int](h)

proc mixColor(a, b: COLORREF, t: float): COLORREF =
  let ar = int(a and 0xFF)
  let ag = int((a shr 8) and 0xFF)
  let ab = int((a shr 16) and 0xFF)
  let br = int(b and 0xFF)
  let bg = int((b shr 8) and 0xFF)
  let bb = int((b shr 16) and 0xFF)
  result = RGB(
    int(ar.float + (br - ar).float * t),
    int(ag.float + (bg - ag).float * t),
    int(ab.float + (bb - ab).float * t)
  )

proc drawGlassPanel(hdc: HDC, rc: RECT, radius: int32) =
  ## 用 GDI 渐变和高光模拟磨砂玻璃质感。
  for y in rc.top ..< rc.bottom:
    let t = if rc.bottom > rc.top: (y - rc.top).float / (rc.bottom - rc.top).float else: 0.0
    let brush = CreateSolidBrush(mixColor(COLOR_BG_TOP, COLOR_BG_BOTTOM, t))
    var lineRc = RECT(left: rc.left, top: y, right: rc.right, bottom: y + 1)
    FillRect(hdc, lineRc.addr, brush)
    DeleteObject(brush)

  let hPen = CreatePen(PS_SOLID, 1, COLOR_BORDER)
  let oldPen = SelectObject(hdc, hPen)
  let oldBrush = SelectObject(hdc, GetStockObject(HOLLOW_BRUSH))
  RoundRect(hdc, rc.left, rc.top, rc.right, rc.bottom, radius, radius)
  SelectObject(hdc, oldBrush)
  SelectObject(hdc, oldPen)
  DeleteObject(hPen)

  let hiPen = CreatePen(PS_SOLID, 1, COLOR_HIGHLIGHT)
  let oldHiPen = SelectObject(hdc, hiPen)
  MoveToEx(hdc, rc.left + 14, rc.top + 1, nil)
  LineTo(hdc, rc.right - 14, rc.top + 1)
  SelectObject(hdc, oldHiPen)
  DeleteObject(hiPen)

proc drawStatusDot(hdc: HDC, x: int32, y: int32, color: COLORREF) =
  let brush = CreateSolidBrush(color)
  let oldBrush = SelectObject(hdc, brush)
  let oldPen = SelectObject(hdc, GetStockObject(NULL_PEN))
  Ellipse(hdc, x, y, x + 7, y + 7)
  SelectObject(hdc, oldPen)
  SelectObject(hdc, oldBrush)
  DeleteObject(brush)

proc drawTextStr(hdc: HDC, text: string, x: int32, y: int32, font: HFONT, color: COLORREF) =
  ## 绘制文本
  var rc: RECT
  rc.left = x
  rc.top = y
  rc.right = x + 500
  rc.bottom = y + 24
  let oldFont = SelectObject(hdc, font)
  SetTextColor(hdc, color)
  SetBkMode(hdc, TRANSPARENT)
  DrawTextW(hdc, text, -1, rc, DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOCLIP)
  SelectObject(hdc, oldFont)

proc drawTextCentered(hdc: HDC, text: string, rc: RECT, font: HFONT, color: COLORREF) =
  let oldFont = SelectObject(hdc, font)
  SetTextColor(hdc, color)
  SetBkMode(hdc, TRANSPARENT)
  var r = rc
  DrawTextW(hdc, text, -1, r, DT_CENTER or DT_VCENTER or DT_SINGLELINE)
  SelectObject(hdc, oldFont)

proc drawMetricRow(hdc: HDC, label, value: string, x: int32, y: int32) =
  ## 固定标签列和数值列，避免中文或长数字互相覆盖。
  const LabelWidth = 58'i32
  let labelColor = COLOR_TEXT
  let valueColor = COLOR_VALUE
  drawTextStr(hdc, label, x, y, gUi.hFont, labelColor)
  drawTextStr(hdc, value, x + LabelWidth, y, gUi.hFontMono, valueColor)

proc formatMiniCount(value: int64): string =
  let absValue = abs(value)
  if absValue >= 1_000_000_000:
    formatFloat(value.float / 1_000_000_000'f64, ffDecimal, 1) & "B"
  elif absValue >= 1_000_000:
    formatFloat(value.float / 1_000_000'f64, ffDecimal, 1) & "M"
  elif absValue >= 1_000:
    formatFloat(value.float / 1_000'f64, ffDecimal, 0) & "K"
  else:
    $value

proc drawTrendRow(hdc: HDC, label: string, values: array[7, int64], x: int32, y: int32) =
  const LabelWidth = 58'i32
  const VisibleDays = 5
  const SlotWidth = 31'i32
  const BarWidth = 16'i32
  drawTextStr(hdc, label, x, y, gUi.hFont, COLOR_TEXT)
  var maxValue: int64 = 0
  for i in 7 - VisibleDays ..< 7:
    let value = values[i]
    if value > maxValue:
      maxValue = value
  let baseX = x + LabelWidth + 6
  let baseY = y + 54
  for i in 0 ..< VisibleDays:
    let value = values[7 - VisibleDays + i]
    let barHeight =
      if maxValue > 0: max(2'i32, int32(value.float / maxValue.float * 24.0))
      else: 2'i32
    let slotLeft = baseX + int32(i) * SlotWidth
    let barLeft = slotLeft + (SlotWidth - BarWidth) div 2
    var textRc = RECT(left: slotLeft - 4, top: y + 8, right: slotLeft + SlotWidth + 4, bottom: y + 22)
    drawTextCentered(hdc, formatMiniCount(value), textRc, gUi.hFontTiny, COLOR_TEXT)
    let brush = CreateSolidBrush(if i == VisibleDays - 1: COLOR_DEEPSEEK else: RGB(67, 74, 88))
    var rc = RECT(left: barLeft, top: baseY - barHeight, right: barLeft + BarWidth, bottom: baseY)
    FillRect(hdc, rc.addr, brush)
    DeleteObject(brush)

proc formatCount(value: int64): string =
  let absValue = abs(value)
  if absValue >= 1_000_000_000:
    result = formatFloat(value.float / 1_000_000_000'f64, ffDecimal, 1) & "B"
  elif absValue >= 1_000_000:
    result = formatFloat(value.float / 1_000_000'f64, ffDecimal, 1) & "M"
  elif absValue >= 1_000:
    result = formatFloat(value.float / 1_000'f64, ffDecimal, 1) & "K"
  else:
    result = $value

proc formatPercent(value: float): string =
  formatFloat(value, ffDecimal, 1) & "%"

proc formatBillTime(ms: int64): string =
  if ms <= 0:
    return "-- --:--"
  when defined(windows):
    let fileMs = uint64(ms + 11_644_473_600_000'i64) * 10_000'u64
    var ft = FILETIME(
      dwLowDateTime: DWORD(fileMs and 0xFFFF_FFFF'u64),
      dwHighDateTime: DWORD(fileMs shr 32)
    )
    var localFt: FILETIME
    var st: SYSTEMTIME
    if FileTimeToLocalFileTime(ft.addr, localFt.addr) != 0 and
        FileTimeToSystemTime(localFt.addr, st.addr) != 0:
      let mo = if st.wMonth < 10: "0" & $st.wMonth else: $st.wMonth
      let dd = if st.wDay < 10: "0" & $st.wDay else: $st.wDay
      let hh = if st.wHour < 10: "0" & $st.wHour else: $st.wHour
      let mm = if st.wMinute < 10: "0" & $st.wMinute else: $st.wMinute
      return mo & "-" & dd & " " & hh & ":" & mm
  "-- --:--"

proc formatDuration(secTotal: int64): string =
  if secTotal <= 0:
    return "0s"
  let h = secTotal div 3600
  let m = (secTotal mod 3600) div 60
  let s = secTotal mod 60
  if h > 0:
    result = "$1h $2m $3s".format($h, $m, $s)
  elif m > 0:
    result = "$1m $2s".format($m, $s)
  else:
    result = "$1s".format($s)

proc activityGlyph(): string =
  case gUi.animationFrame mod 3
  of 0: result = ".  "
  of 1: result = " . "
  else: result = "  ."

proc drawSection(hdc: HDC, data: MonitorData, x: int32, y: int32): int32 =
  ## 绘制一个工具区域，返回下一区域的 Y 坐标
  var cy = y
  let running = data.status == tsRunning
  let statusText = if running: "执行中" else: "空闲"
  let accent = if data.tool == ttCodex: COLOR_CODEX else: COLOR_GREEN

  # 标题行: 工具名 + 状态
  drawTextStr(hdc, data.name, x, cy, gUi.hFontHeader, COLOR_TEXT_BRIGHT)
  let nameW: int32 = 70
  drawStatusDot(hdc, x + nameW, cy + 8, if running: accent else: COLOR_GRAY)
  drawTextStr(hdc, " " & statusText, x + nameW + 12, cy + 1, gUi.hFont, if running: accent else: COLOR_GRAY)
  cy += HEADER_HEIGHT + 2

  # 信息行
  let indent: int32 = x + 6

  # Session 时长
  let durSec = data.sessionDurationSec
  let durStr = formatDuration(durSec)
  drawMetricRow(hdc, "本次", durStr, indent, cy)
  cy += ROW_HEIGHT

  # Session Token
  let tokStr = if data.answering: activityGlyph() else: formatCount(data.sessionTokens)
  drawMetricRow(hdc, "Token", tokStr, indent, cy)
  cy += ROW_HEIGHT

  # Session Cache
  let cacheStr = if data.answering: activityGlyph() else: formatCount(data.sessionCacheTokens)
  drawMetricRow(hdc, "缓存", cacheStr, indent, cy)
  cy += ROW_HEIGHT

  # 今日累计
  let todayStr = formatCount(data.todayTokens)
  drawMetricRow(hdc, "今日", todayStr, indent, cy)
  cy += ROW_HEIGHT

  result = cy

proc drawDeepSeekSection(hdc: HDC, data: DeepSeekData, x: int32, y: int32): int32 =
  var cy = y
  drawTextStr(hdc, "DeepSeek", x, cy, gUi.hFontHeader, COLOR_TEXT_BRIGHT)
  drawTextStr(hdc, formatBillTime(data.billUpdatedMs), x + 116, cy + 1, gUi.hFont, COLOR_TEXT)
  cy += HEADER_HEIGHT + 2

  let indent: int32 = x + 6
  if data.billStale:
    drawMetricRow(hdc, "账单", "未落账", indent, cy)
    cy += ROW_HEIGHT

  drawMetricRow(hdc, "费用", formatDeepSeekMoney(data.todayCost, "USD"), indent, cy)
  cy += ROW_HEIGHT

  let balanceText =
    if data.balanceOk: formatDeepSeekMoney(data.balance, data.balanceCurrency)
    else: "-"
  drawMetricRow(hdc, "余额", balanceText, indent, cy)
  cy += ROW_HEIGHT

  drawMetricRow(hdc, "Token", formatCount(data.todayTokens), indent, cy)
  cy += ROW_HEIGHT

  drawMetricRow(hdc, "命中", formatPercent(data.cacheHitRate), indent, cy)
  cy += ROW_HEIGHT + 8

  drawTrendRow(hdc, "趋势", data.weekTokens, indent, cy)
  cy += ROW_HEIGHT + 44
  result = cy

proc drawModeButton(hdc: HDC) =
  var rc = RECT(left: WIN_WIDTH - 34, top: 9, right: WIN_WIDTH - 12, bottom: 29)
  drawTextCentered(hdc, "_", rc, gUi.hFontHeader, COLOR_TEXT)

proc drawCompactStatus(hdc: HDC, label: string, data: MonitorData, x: int32) =
  let running = data.status == tsRunning
  let dotColor = if running: COLOR_GREEN else: COLOR_GRAY
  drawTextStr(hdc, label, x, 10, gUi.hFont, COLOR_TEXT_BRIGHT)
  drawStatusDot(hdc, x + 52, 16, dotColor)
  drawTextStr(hdc, formatCount(data.todayTokens), x + 66, 10, gUi.hFontMono, COLOR_VALUE)

proc drawCompactDeepSeek(hdc: HDC, x: int32) =
  let data = gUi.monitor.deepseekData
  drawTextStr(hdc, "DS", x, 10, gUi.hFont, COLOR_TEXT_BRIGHT)
  let dotColor =
    if data.billStale: COLOR_CODEX
    elif data.balanceOk: COLOR_DEEPSEEK
    else: COLOR_GRAY
  drawStatusDot(hdc, x + 30, 16, dotColor)
  drawTextStr(hdc, formatDeepSeekMoney(data.todayCost, "USD"), x + 44, 10, gUi.hFontMono, COLOR_VALUE)

proc drawCompactWindow(hdc: HDC, rc: RECT) =
  drawGlassPanel(hdc, rc, 12)
  drawCompactStatus(hdc, "Claude", gUi.monitor.claudeData, 16)
  drawCompactStatus(hdc, "Codex", gUi.monitor.codexData, 138)
  drawCompactDeepSeek(hdc, 266)
  var restoreRc = RECT(left: COMPACT_WIDTH - 34, top: 8, right: COMPACT_WIDTH - 10, bottom: 30)
  drawTextCentered(hdc, "▴", restoreRc, gUi.hFontHeader, COLOR_TEXT)

proc drawSeparator(hdc: HDC, x: int32, y: int32, width: int32) =
  let hPen = CreatePen(PS_SOLID, 1, COLOR_SEPARATOR)
  let oldPen = SelectObject(hdc, hPen)
  MoveToEx(hdc, x + PADDING + 2, y, nil)
  LineTo(hdc, x + width - PADDING - 2, y)
  SelectObject(hdc, oldPen)
  DeleteObject(hPen)

proc paintWindow(hwnd: HWND) =
  ## 双缓冲绘制
  var ps: PAINTSTRUCT
  let hdc = BeginPaint(hwnd, ps.addr)
  var rc: RECT
  GetClientRect(hwnd, rc.addr)

  # 创建双缓冲
  let memDc = CreateCompatibleDC(hdc)
  let memBmp = CreateCompatibleBitmap(hdc, rc.right - rc.left, rc.bottom - rc.top)
  let oldBmp = SelectObject(memDc, memBmp)

  # 绘制背景

  if gUi.mode == umCompact:
    drawCompactWindow(memDc, rc)
    BitBlt(hdc, 0, 0, rc.right - rc.left, rc.bottom - rc.top, memDc, 0, 0, SRCCOPY)
    SelectObject(memDc, oldBmp)
    DeleteObject(memBmp)
    DeleteDC(memDc)
    EndPaint(hwnd, ps.addr)
    return

  # 绘制 Claude 区域
  drawGlassPanel(memDc, rc, 12)
  let claudeEndY = drawSection(memDc, gUi.monitor.claudeData, PADDING + 2, PADDING)

  # 分隔线
  drawSeparator(memDc, 0, claudeEndY + SECTION_GAP, WIN_WIDTH)

  # 绘制 Codex 区域
  let codexStartY = claudeEndY + SECTION_GAP + 5
  let codexEndY = drawSection(memDc, gUi.monitor.codexData, PADDING + 2, codexStartY)
  drawSeparator(memDc, 0, codexEndY + SECTION_GAP, WIN_WIDTH)

  let deepSeekStartY = codexEndY + SECTION_GAP + 5
  discard drawDeepSeekSection(memDc, gUi.monitor.deepseekData, PADDING + 2, deepSeekStartY)
  drawModeButton(memDc)

  # Blit 到屏幕
  BitBlt(hdc, 0, 0, rc.right - rc.left, rc.bottom - rc.top, memDc, 0, 0, SRCCOPY)

  # 清理
  SelectObject(memDc, oldBmp)
  DeleteObject(memBmp)
  DeleteDC(memDc)
  EndPaint(hwnd, ps.addr)

proc updateWindowStyle(hwnd: HWND, config: AppConfig) =
  ## 更新窗口样式（置顶、透明度、穿透）
  var exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE)

  # 置顶
  SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)

  # 透明度
  let alpha = clamp(int32(config.opacity * 255), 26, 255)
  SetLayeredWindowAttributes(hwnd, 0, alpha.byte, LWA_ALPHA)

  # 鼠标穿透
  if config.clickThrough:
    exStyle = exStyle or WS_EX_TRANSPARENT
    SetWindowLongW(hwnd, GWL_EXSTYLE, exStyle)
  else:
    exStyle = exStyle and (not WS_EX_TRANSPARENT)
    SetWindowLongW(hwnd, GWL_EXSTYLE, exStyle)

proc calcWindowHeight(): int32 =
  result = WIN_HEIGHT.int32

proc compactY(): int32 =
  var rc: RECT
  discard SystemParametersInfoW(SPI_GETWORKAREA, 0, rc.addr, 0)
  result = rc.bottom - COMPACT_HEIGHT - 1

proc clampToWorkArea(x, y, width, height: int32): POINT =
  var work: RECT
  discard SystemParametersInfoW(SPI_GETWORKAREA, 0, work.addr, 0)
  result.x = x
  result.y = y
  if result.x < work.left: result.x = work.left
  if result.y < work.top: result.y = work.top
  if result.x > work.right - width: result.x = work.right - width
  if result.y > work.bottom - height: result.y = work.bottom - height

proc compactX(configX: int): int32 =
  var rc: RECT
  discard SystemParametersInfoW(SPI_GETWORKAREA, 0, rc.addr, 0)
  let defaultX = rc.right - COMPACT_WIDTH
  result = if configX >= rc.left and configX <= rc.right - COMPACT_WIDTH: configX.int32 else: defaultX.int32

proc defaultFullPosition(configX, configY: int): POINT =
  var work: RECT
  discard SystemParametersInfoW(SPI_GETWORKAREA, 0, work.addr, 0)
  let x = if configX >= work.left and configX <= work.right - WIN_WIDTH: configX.int32 else: work.right - WIN_WIDTH
  let y = if configY >= work.top and configY <= work.bottom - WIN_HEIGHT: configY.int32 else: work.top
  result = clampToWorkArea(x, y, WIN_WIDTH.int32, WIN_HEIGHT.int32)

proc applyWindowMode(hwnd: HWND) =
  let width = (if gUi.mode == umCompact: COMPACT_WIDTH else: WIN_WIDTH).int32
  let height = (if gUi.mode == umCompact: COMPACT_HEIGHT else: WIN_HEIGHT).int32
  var x: int32
  var y: int32
  if gUi.mode == umCompact:
    x = compactX(gUi.monitor.config.compactWindowX)
    y = compactY()
  else:
    let pt = defaultFullPosition(gUi.monitor.config.windowX, gUi.monitor.config.windowY)
    x = pt.x
    y = pt.y

  SetWindowPos(hwnd, HWND_BOTTOM, x, y, width, height, SWP_NOACTIVATE)
  var r: RECT
  GetClientRect(hwnd, r.addr)
  let hRgn = CreateRoundRectRgn(0, 0, r.right + 1, r.bottom + 1, 12, 12)
  SetWindowRgn(hwnd, hRgn, TRUE)
  InvalidateRect(hwnd, nil, TRUE)

proc switchMode(hwnd: HWND, mode: UiMode) =
  var rc: RECT
  if GetWindowRect(hwnd, rc.addr) != 0:
    if gUi.mode == umFull:
      gUi.monitor.config.windowX = rc.left
      gUi.monitor.config.windowY = rc.top
    else:
      gUi.monitor.config.compactWindowX = rc.left
  gUi.mode = mode
  applyWindowMode(hwnd)

proc saveCurrentWindowPosition*(hwnd: HWND) =
  if gUi.isNil:
    return
  var rc: RECT
  if GetWindowRect(hwnd, rc.addr) == 0:
    return
  if gUi.mode == umCompact:
    gUi.monitor.config.compactWindowX = rc.left
  else:
    gUi.monitor.config.windowX = rc.left
    gUi.monitor.config.windowY = rc.top

proc reloadConfigIfChanged(hwnd: HWND) =
  if not changed(gUi.configWatcher):
    return
  saveCurrentWindowPosition(hwnd)
  var next = loadConfig()
  if next.windowX < 0:
    next.windowX = gUi.monitor.config.windowX
  if next.windowY < 0:
    next.windowY = gUi.monitor.config.windowY
  if next.compactWindowX < 0:
    next.compactWindowX = gUi.monitor.config.compactWindowX
  let intervalChanged = next.refreshInterval != gUi.monitor.config.refreshInterval
  applyConfig(gUi.monitor, next)
  updateWindowStyle(hwnd, gUi.monitor.config)
  if intervalChanged:
    KillTimer(hwnd, cast[UINT_PTR](1))
    SetTimer(hwnd, cast[UINT_PTR](1), cast[UINT](gUi.monitor.config.refreshInterval), nil)
  InvalidateRect(hwnd, nil, TRUE)

proc WndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_CREATE:
    SetWindowLongW(hwnd, GWL_EXSTYLE,
      GetWindowLongW(hwnd, GWL_EXSTYLE) or WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE)
    SetLayeredWindowAttributes(hwnd, 0, (gUi.monitor.config.opacity * 255).int32.byte, LWA_ALPHA)
    SetTimer(hwnd, cast[UINT_PTR](1), cast[UINT](gUi.monitor.config.refreshInterval), nil)
    return 0

  of WM_PAINT:
    paintWindow(hwnd)
    return 0

  of WM_TIMER:
    if wParam == 1:
      reloadConfigIfChanged(hwnd)
      refreshAll(gUi.monitor)
      let claudeHash = dataHash(gUi.monitor.claudeData)
      let codexHash = dataHash(gUi.monitor.codexData)
      let deepseekHash = deepSeekHash(gUi.monitor.deepseekData)
      let animating = gUi.monitor.claudeData.answering or gUi.monitor.codexData.answering
      if animating:
        inc gUi.animationFrame
      else:
        discard
      if claudeHash != gUi.lastClaudeHash or codexHash != gUi.lastCodexHash or
          deepseekHash != gUi.lastDeepSeekHash or animating:
        gUi.lastClaudeHash = claudeHash
        gUi.lastCodexHash = codexHash
        gUi.lastDeepSeekHash = deepseekHash
        InvalidateRect(hwnd, nil, TRUE)
    return 0

  of WM_REFRESH_DATA:
    refreshAll(gUi.monitor)
    InvalidateRect(hwnd, nil, TRUE)
    return 0

  of WM_TRAY_ICON:
    # V4 行为下 lParam = MAKELPARAM(event, iconID), 需要取 LOWORD
    let event = cast[int](lParam) and 0xFFFF
    # 右键: 显示菜单
    if event == WM_RBUTTONDOWN or event == WM_RBUTTONUP or
       event == WM_CONTEXTMENU or event == NIN_KEYSELECT:
      showTrayMenu(hwnd)
    return 0

  of WM_LBUTTONDOWN:
    let x = cast[int32](GET_X_LPARAM(lParam))
    let y = cast[int32](GET_Y_LPARAM(lParam))
    if gUi.mode == umCompact:
      if x >= COMPACT_WIDTH - 42 and y >= 0 and y <= COMPACT_HEIGHT:
        switchMode(hwnd, umFull)
      else:
        gUi.draggingCompact = true
        gUi.dragOffsetX = x
        SetCapture(hwnd)
      return 0
    else:
      if x >= WIN_WIDTH - 40 and x <= WIN_WIDTH - 8 and y >= 4 and y <= 34:
        switchMode(hwnd, umCompact)
        return 0
    return 0

  of WM_MOUSEMOVE:
    if gUi.mode == umCompact and gUi.draggingCompact:
      var pt: POINT
      GetCursorPos(pt.addr)
      var work: RECT
      discard SystemParametersInfoW(SPI_GETWORKAREA, 0, work.addr, 0)
      var newX = pt.x - gUi.dragOffsetX
      if newX < work.left: newX = work.left
      if newX > work.right - COMPACT_WIDTH: newX = work.right - COMPACT_WIDTH
      SetWindowPos(hwnd, HWND_BOTTOM, newX, compactY(),
        COMPACT_WIDTH, COMPACT_HEIGHT, SWP_NOACTIVATE)
      return 0

  of WM_LBUTTONUP:
    if gUi.draggingCompact:
      gUi.draggingCompact = false
      ReleaseCapture()
      var rc: RECT
      if GetWindowRect(hwnd, rc.addr) != 0:
        gUi.monitor.config.compactWindowX = rc.left
      return 0

  of WM_WINDOWPOSCHANGING:
    let wp = cast[ptr WINDOWPOS](lParam)
    if wp != nil and (wp.flags and SWP_NOMOVE) == 0:
      if gUi.mode == umCompact:
        var work: RECT
        discard SystemParametersInfoW(SPI_GETWORKAREA, 0, work.addr, 0)
        if wp.x < work.left: wp.x = work.left
        if wp.x > work.right - COMPACT_WIDTH: wp.x = work.right - COMPACT_WIDTH
        wp.y = compactY()
      else:
        let pt = clampToWorkArea(wp.x, wp.y, WIN_WIDTH.int32, WIN_HEIGHT.int32)
        wp.x = pt.x
        wp.y = pt.y
    return DefWindowProc(hwnd, msg, wParam, lParam)

  of WM_NCHITTEST:
    if gUi.mode == umCompact:
      return HTCLIENT
    let hitX: int32 = cast[int32](GET_X_LPARAM(lParam))
    let hitY: int32 = cast[int32](GET_Y_LPARAM(lParam))
    var hitRc: RECT
    GetWindowRect(hwnd, hitRc.addr)
    let localX = hitX - hitRc.left
    let localY = hitY - hitRc.top
    if localX >= WIN_WIDTH - 40 and localX <= WIN_WIDTH - 8 and localY >= 4 and localY <= 34:
      return HTCLIENT
    let ptX: int32 = cast[int32](GET_X_LPARAM(lParam))
    let ptY: int32 = cast[int32](GET_Y_LPARAM(lParam))
    let pt = POINT(x: ptX, y: ptY)
    var rc: RECT
    GetWindowRect(hwnd, rc.addr)
    if pt.x >= rc.left and pt.x <= rc.right and pt.y >= rc.top and pt.y <= rc.bottom:
      return HTCAPTION
    return DefWindowProc(hwnd, msg, wParam, lParam)

  of WM_DESTROY:
    KillTimer(hwnd, cast[UINT_PTR](1))
    close(gUi.configWatcher)
    cleanupGdi()
    PostQuitMessage(0)
    return 0

  else:
    return DefWindowProc(hwnd, msg, wParam, lParam)

proc createWindow*(monitor: Monitor): HWND =
  gUi = UiContext(monitor: monitor, mode: umFull)
  gUi.configWatcher = initDirectoryWatcher(getCurrentDir(), recursive = false)
  initGdi()

  let hInstance = GetModuleHandleW(nil)

  var wc: WNDCLASSW
  wc.lpfnWndProc = WndProc
  wc.hInstance = hInstance
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.hbrBackground = cast[HBRUSH](0)
  wc.lpszClassName = WINDOW_CLASS
  wc.style = CS_HREDRAW or CS_VREDRAW
  discard RegisterClassW(wc.addr)

  let initialPos = defaultFullPosition(monitor.config.windowX, monitor.config.windowY)
  var x: int32 = initialPos.x
  var y: int32 = initialPos.y

  let height: int32 = calcWindowHeight()

  let exStyle: DWORD = WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE
  result = CreateWindowExW(
    exStyle,
    WINDOW_CLASS, WINDOW_TITLE,
    WS_POPUP,
    x, y, WIN_WIDTH, height,
    cast[HWND](0), cast[HMENU](0), cast[HINSTANCE](hInstance), nil
  )

  gUi.hwnd = result
  updateWindowStyle(result, monitor.config)

  var rc: RECT
  GetClientRect(result, rc.addr)
  let hRgn = CreateRoundRectRgn(0, 0, rc.right + 1, rc.bottom + 1, 12, 12)
  SetWindowRgn(result, hRgn, TRUE)

  ShowWindow(result, SW_SHOWNOACTIVATE)
  SetWindowPos(result, HWND_BOTTOM, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)
  UpdateWindow(result)
