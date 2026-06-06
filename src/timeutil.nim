import std/[os, strutils]

when defined(windows):
  import winim/lean

proc pad2(n: int): string =
  if n < 10: "0" & $n else: $n

proc pad4(n: int): string =
  let s = $n
  repeat("0", max(0, 4 - s.len)) & s

proc todayParts*(): tuple[year, month, day: int] =
  when defined(windows):
    var st: SYSTEMTIME
    GetLocalTime(st.addr)
    result = (int(st.wYear), int(st.wMonth), int(st.wDay))
  else:
    result = (1970, 1, 1)

proc todayKey*(): string =
  let t = todayParts()
  pad4(t.year) & "-" & pad2(t.month) & "-" & pad2(t.day)

proc dateKey*(year, month, day: int): string =
  pad4(year) & "-" & pad2(month) & "-" & pad2(day)

proc todayPath*(root: string): string =
  let t = todayParts()
  root / pad4(t.year) / pad2(t.month) / pad2(t.day)

proc nowUnixMs*(): int64 =
  when defined(windows):
    var ft: FILETIME
    GetSystemTimeAsFileTime(ft.addr)
    let high = uint64(cast[uint32](ft.dwHighDateTime))
    let low = uint64(cast[uint32](ft.dwLowDateTime))
    let ticks = (high shl 32) or low
    result = int64(ticks div 10_000'u64) - 11_644_473_600_000'i64
  else:
    result = 0

proc localDateKeyFromUnixMs*(unixMs: int64): string =
  when defined(windows):
    if unixMs <= 0:
      return ""
    let ticks = (uint64(unixMs + 11_644_473_600_000'i64)) * 10_000'u64
    var utcFt: FILETIME
    utcFt.dwLowDateTime = cast[DWORD](ticks and 0xFFFF_FFFF'u64)
    utcFt.dwHighDateTime = cast[DWORD](ticks shr 32)
    var localFt: FILETIME
    var st: SYSTEMTIME
    if FileTimeToLocalFileTime(utcFt.addr, localFt.addr) == 0:
      return ""
    if FileTimeToSystemTime(localFt.addr, st.addr) == 0:
      return ""
    result = dateKey(int(st.wYear), int(st.wMonth), int(st.wDay))
  else:
    result = ""

proc toInt2(s: string, pos: int): int =
  if pos + 1 >= s.len: return -1
  if s[pos] notin {'0'..'9'} or s[pos + 1] notin {'0'..'9'}: return -1
  (ord(s[pos]) - ord('0')) * 10 + ord(s[pos + 1]) - ord('0')

proc toInt4(s: string, pos: int): int =
  if pos + 3 >= s.len: return -1
  for i in pos .. pos + 3:
    if s[i] notin {'0'..'9'}: return -1
  (ord(s[pos]) - ord('0')) * 1000 +
    (ord(s[pos + 1]) - ord('0')) * 100 +
    (ord(s[pos + 2]) - ord('0')) * 10 +
    ord(s[pos + 3]) - ord('0')

proc daysFromCivil(year, month, day: int): int64 =
  var y = year
  let m = month
  y -= (if m <= 2: 1 else: 0)
  let era = y div 400
  let yoe = y - era * 400
  let mp = m + (if m > 2: -3 else: 9)
  let doy = (153 * mp + 2) div 5 + day - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  int64(era * 146097 + doe - 719468)

proc parseIsoUnixMs*(value: string): int64 =
  if value.len < 20:
    return 0
  let year = toInt4(value, 0)
  let month = toInt2(value, 5)
  let day = toInt2(value, 8)
  let hour = toInt2(value, 11)
  let minute = toInt2(value, 14)
  let second = toInt2(value, 17)
  if year < 1970 or month < 1 or month > 12 or day < 1 or day > 31 or
      hour < 0 or minute < 0 or second < 0:
    return 0
  var ms = 0
  if value.len >= 24 and value[19] == '.':
    let a = toInt2(value, 20)
    if a >= 0 and value[22] in {'0'..'9'}:
      ms = a * 10 + ord(value[22]) - ord('0')
  result = daysFromCivil(year, month, day) * 86_400_000'i64 +
    int64(hour * 3_600_000 + minute * 60_000 + second * 1000 + ms)
