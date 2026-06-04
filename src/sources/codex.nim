## Codex CLI 数据源解析

import std/[os, strutils]
import ../models
import ../jsonlite
import ../timeutil

const
  CodexDir = ".codex"
  CodexSessionsDir = "sessions"

proc getCodexHome*(): string =
  let userProfile = getEnv("USERPROFILE")
  if userProfile.len > 0:
    result = userProfile / CodexDir
  else:
    result = getHomeDir() / CodexDir

proc getCodexSessionsRoot*(): string =
  result = getCodexHome() / CodexSessionsDir

proc findLatestCodexJsonl*(root: string): string =
  result = ""
  if not dirExists(root): return
  let dir = todayPath(root)
  if not dirExists(dir): return
  var latestName = ""
  for file in walkDirRec(dir):
    let name = extractFilename(file)
    if not (name.startsWith("rollout-") and name.endsWith(".jsonl")):
      continue
    if name > latestName:
      latestName = name
      result = file

proc parseCodexTurnState*(jsonlPath: string): CodexTurnState =
  if not fileExists(jsonlPath):
    return result
  var lastUserMs: int64 = 0
  var lastFinalMs: int64 = 0
  try:
    var f: File
    if not open(f, jsonlPath, fmRead):
      return result
    defer: close(f)

    var line: string
    while readLine(f, line):
      if line.len == 0:
        continue
      try:
        let tsText = getJsonString(line, "timestamp")
        if tsText.len == 0:
          continue
        let ts = parseIsoUnixMs(tsText)
        if ts <= 0:
          continue
        if lastUserMs > 0:
          result.lastEventMs = ts

        if line.contains("\"type\":\"event_msg\"") or line.contains("\"type\": \"event_msg\""):
          if line.contains("\"type\":\"user_message\"") or line.contains("\"type\": \"user_message\""):
            lastUserMs = ts
            result.lastEventMs = ts
            lastFinalMs = 0
          elif (line.contains("\"type\":\"agent_message\"") or line.contains("\"type\": \"agent_message\"")) and
              (line.contains("\"phase\":\"final_answer\"") or line.contains("\"phase\": \"final_answer\"")):
            lastFinalMs = ts
      except:
        discard
  except:
    return result

  if lastUserMs <= 0:
    return result
  let nowMs = nowUnixMs()
  result.startMs = lastUserMs
  result.answering = lastFinalMs <= lastUserMs
  let endMs = if result.answering: nowMs else: lastFinalMs
  if endMs > lastUserMs:
    result.durationSec = (endMs - lastUserMs) div 1000
  else:
    result.durationSec = 0

proc findTodayCodexJsonls*(root: string): seq[string] =
  result = @[]
  if not dirExists(root): return
  let todayDir = todayPath(root)
  if dirExists(todayDir):
    for file in walkDirRec(todayDir):
      let name = extractFilename(file)
      if name.startsWith("rollout-") and name.endsWith(".jsonl"):
        result.add(file)

proc parseCodexTokenCount*(jsonlPath: string): CodexTokenInfo =
  if not fileExists(jsonlPath):
    return result
  try:
    var f: File
    if not open(f, jsonlPath, fmRead):
      return
    defer: close(f)
    var line: string
    var lastTokenLine = ""
    while readLine(f, line):
      if line.contains("\"token_count\""):
        lastTokenLine = line
    if lastTokenLine.len > 0:
      let totalPart = getJsonObject(lastTokenLine, "total_token_usage")
      if totalPart.len > 0:
        result.cachedInputTokens = getJsonInt64(totalPart, "cached_input_tokens")
        result.totalTokens = getJsonInt64(totalPart, "total_tokens")
      let lastPart = getJsonObject(lastTokenLine, "last_token_usage")
      if lastPart.len > 0:
        result.lastCachedInputTokens = getJsonInt64(lastPart, "cached_input_tokens")
        result.lastTotalTokens = getJsonInt64(lastPart, "total_tokens")
  except:
    discard

proc aggregateTodayCodexTokens*(root: string): tuple[tokens, cache: int64] =
  result = (0, 0)
  let files = findTodayCodexJsonls(root)
  for file in files:
    let info = parseCodexTokenCount(file)
    result.tokens += info.totalTokens
    result.cache += info.cachedInputTokens
