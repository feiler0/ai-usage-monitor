## DeepSeek usage and balance data source

import std/[os, strutils, times]
import ../models
import ../jsonlite

when defined(windows):
  import winim/lean
  import winim/inc/winhttp

const
  UsageFile = ".reasonix" / "usage.jsonl"
  ApiHost = "api.deepseek.com"
  BalancePath = "/user/balance"
  BalanceRefreshMs* = 60_000'i64
  DayMs = 86_400_000'i64

proc getReasonixUsagePath*(): string =
  getHomeDir() / UsageFile

proc getReasonixSessionsDir*(): string =
  getEnv("APPDATA") / "reasonix" / "sessions"

proc findLatestReasonixSessionMs*(dir: string = getReasonixSessionsDir()): int64 =
  if not dirExists(dir):
    return 0
  var latest: Time
  for file in walkFiles(dir / "*.jsonl"):
    let modified = getLastModificationTime(file)
    if result == 0 or modified > latest:
      latest = modified
      result = modified.toUnix() * 1000

proc currencySymbol(code: string): string =
  case code.toUpperAscii()
  of "CNY", "RMB": "\194\165"
  of "USD": "$"
  else: code & " "

proc parseUsageStats*(path: string = getReasonixUsagePath()): DeepSeekData =
  result.balanceCurrency = "USD"
  if not fileExists(path):
    return

  try:
    var f: File
    if not open(f, path, fmRead):
      return
    defer: close(f)

    var line: string
    while readLine(f, line):
      if line.len == 0:
        continue
      let ts = getJsonInt64(line, "ts")
      if ts > result.billUpdatedMs:
        result.billUpdatedMs = ts
  except:
    discard

  if result.billUpdatedMs <= 0:
    return

  # Use the latest billing day with data, so stale-but-valid Reasonix usage
  # does not render as all zero after midnight.
  let latestDayStart = result.billUpdatedMs - (result.billUpdatedMs mod DayMs)
  let weekStart = latestDayStart - 6 * DayMs
  var todayCost = 0.0
  var todayTokens: int64 = 0
  var hit: int64 = 0
  var miss: int64 = 0

  try:
    var f: File
    if not open(f, path, fmRead):
      return
    defer: close(f)

    var line: string
    while readLine(f, line):
      if line.len == 0:
        continue
      let ts = getJsonInt64(line, "ts")
      if ts < weekStart or ts >= latestDayStart + DayMs:
        continue

      let tokens = getJsonInt64(line, "promptTokens") + getJsonInt64(line, "completionTokens")
      let dayIndex = int((ts - weekStart) div DayMs)
      if dayIndex >= 0 and dayIndex < 7:
        result.weekTokens[dayIndex] += tokens

      if ts >= latestDayStart:
        todayCost += getJsonFloat(line, "costUsd")
        todayTokens += tokens
        hit += getJsonInt64(line, "cacheHitTokens")
        miss += getJsonInt64(line, "cacheMissTokens")
  except:
    discard

  result.todayCost = todayCost
  result.todayTokens = todayTokens
  if hit + miss > 0:
    result.cacheHitRate = hit.float * 100.0 / (hit + miss).float

proc parseKeyLine(line: string): string =
  let p = line.find('=')
  if p < 0:
    return ""
  let key = line[0 ..< p].strip().strip(chars = {'"', '\''})
  if not (key.contains("DEEPSEEK") or key == "API_KEY" or key == "apiKey" or key == "api_key"):
    return ""
  line[p + 1 .. ^1].strip().strip(chars = {'"', '\''})

proc parseApiKey(content: string): string =
  result = getJsonString(content, "apiKey")
  if result.len == 0:
    result = getJsonString(content, "api_key")
  if result.len > 0:
    return
  for line in content.splitLines():
    result = parseKeyLine(line)
    if result.len > 0:
      return

proc findDeepSeekApiKey*(): string =
  result = getEnv("DEEPSEEK_API_KEY")
  if result.len > 0:
    return

  let paths = [
    getEnv("USERPROFILE") / ".reasonix" / ".env",
    getEnv("USERPROFILE") / ".reasonix" / "config.json",
    getEnv("APPDATA") / "reasonix" / "credentials",
    getEnv("APPDATA") / "reasonix" / "config.toml",
  ]
  for path in paths:
    if not fileExists(path):
      continue
    try:
      result = parseApiKey(readFile(path))
      if result.len > 0:
        return
    except:
      discard

when defined(windows):
  proc winHttpReadAll(request: HINTERNET): string =
    var available: DWORD = 0
    while WinHttpQueryDataAvailable(request, available.addr) != 0 and available > 0:
      let oldLen = result.len
      result.setLen(oldLen + int(available))
      var read: DWORD = 0
      if WinHttpReadData(request, result[oldLen].addr, available, read.addr) == 0:
        result.setLen(oldLen)
        break
      result.setLen(oldLen + int(read))

  proc fetchBalanceJson(apiKey: string): string =
    if apiKey.len == 0:
      return ""
    let session = WinHttpOpen("AI Usage Monitor", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)
    if session == nil:
      return ""
    defer: WinHttpCloseHandle(session)
    discard WinHttpSetTimeouts(session, 2000, 2000, 3000, 3000)

    let connect = WinHttpConnect(session, ApiHost, INTERNET_DEFAULT_HTTPS_PORT, 0)
    if connect == nil:
      return ""
    defer: WinHttpCloseHandle(connect)

    let request = WinHttpOpenRequest(connect, "GET", BalancePath, nil,
      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE)
    if request == nil:
      return ""
    defer: WinHttpCloseHandle(request)

    let headers = "Authorization: Bearer " & apiKey & "\r\nAccept: application/json\r\n"
    if WinHttpSendRequest(request, headers, DWORD(-1), nil, 0, 0, 0) == 0:
      return ""
    if WinHttpReceiveResponse(request, nil) == 0:
      return ""
    winHttpReadAll(request)

proc refreshBalance*(data: var DeepSeekData) =
  when defined(windows):
    let json = fetchBalanceJson(findDeepSeekApiKey())
    if json.len == 0:
      data.balanceOk = false
      return
    data.balanceAvailable = getJsonBool(json, "is_available", false)
    data.balanceCurrency = getJsonString(json, "currency", data.balanceCurrency)
    let text = getJsonString(json, "total_balance")
    try:
      data.balance = parseFloat(text)
      data.balanceOk = true
    except:
      data.balanceOk = false
  else:
    data.balanceOk = false

proc formatDeepSeekMoney*(value: float, currency: string): string =
  currencySymbol(currency) & formatFloat(value, ffDecimal, 2)
