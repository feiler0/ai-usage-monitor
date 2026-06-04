## stats.json 持久化存储

import std/os
import models
import jsonlite
import timeutil

const
  StatsPath* = "stats.json"
  BackupSuffix = ".bak"

proc parseDate*(): string =
  result = todayKey()

proc loadStats*(path: string = StatsPath): AppStats =
  result = AppStats(lastDate: parseDate())
  if not fileExists(path):
    return result
  try:
    let content = readFile(path)
    if content.len == 0:
      return result
    result.claudeTodayTokens = getJsonInt64(content, "claudeTodayTokens", result.claudeTodayTokens)
    result.claudeTodayCacheTokens = getJsonInt64(content, "claudeTodayCacheTokens", result.claudeTodayCacheTokens)
    result.codexTodayTokens = getJsonInt64(content, "codexTodayTokens", result.codexTodayTokens)
    result.codexTodayCacheTokens = getJsonInt64(content, "codexTodayCacheTokens", result.codexTodayCacheTokens)
    result.lastDate = getJsonString(content, "lastDate", result.lastDate)
    let today = parseDate()
    if result.lastDate != today:
      result.claudeTodayTokens = 0
      result.claudeTodayCacheTokens = 0
      result.codexTodayTokens = 0
      result.codexTodayCacheTokens = 0
      result.lastDate = today
  except:
    try:
      copyFile(path, path & BackupSuffix)
    except:
      discard
    result = AppStats(lastDate: parseDate())

proc saveStats*(stats: AppStats, path: string = StatsPath) =
  let content = "{\n" &
    "  \"claudeTodayTokens\": " & $stats.claudeTodayTokens & ",\n" &
    "  \"claudeTodayCacheTokens\": " & $stats.claudeTodayCacheTokens & ",\n" &
    "  \"codexTodayTokens\": " & $stats.codexTodayTokens & ",\n" &
    "  \"codexTodayCacheTokens\": " & $stats.codexTodayCacheTokens & ",\n" &
    "  \"lastDate\": \"" & jsonEscape(stats.lastDate) & "\"\n" &
    "}"
  let tmpPath = path & ".tmp"
  try:
    writeFile(tmpPath, content)
    moveFile(tmpPath, path)
  except:
    discard
