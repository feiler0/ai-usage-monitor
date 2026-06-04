## Claude Code CLI 数据源解析

import std/[algorithm, os, strutils]
import ../models
import ../jsonlite
import ../timeutil

const
  ClaudeDir = ".claude"
  ProjectTimeDir = "project-time"

proc getClaudeHome*(): string =
  result = getHomeDir() / ClaudeDir

proc getProjectTimeDir*(): string =
  result = getClaudeHome() / ProjectTimeDir

proc parseClaudeProjectSnapshots*(dir: string): seq[ClaudeProjectSnapshot] =
  result = @[]
  if not dirExists(dir):
    return

  let nowMs = nowUnixMs()
  for file in walkFiles(dir / "*.json"):
    let filename = extractFilename(file)
    if filename.endsWith("-state.json") or filename.startsWith("_"):
      continue

    try:
      let totals = readFile(file)
      let slug = filename[0 ..< filename.len - ".json".len]
      let statePath = dir / (slug & "-state.json")

      var answering = false
      var lastPromptAt: int64 = 0
      var lastAnswerDurationMs: int64 = 0
      var lastTurnTokens: int64 = 0
      var lastTurnCacheTokens: int64 = 0
      var lastUpdateAt: int64 = 0
      var lastActiveAt: int64 = 0

      if fileExists(statePath):
        try:
          let state = readFile(statePath)
          answering = getJsonBool(state, "answering")
          lastPromptAt = getJsonInt64(state, "last_prompt_at")
          lastAnswerDurationMs = getJsonInt64(state, "last_answer_duration_ms")
          lastTurnTokens = getJsonInt64(state, "last_turn_tokens")
          lastTurnCacheTokens = getJsonInt64(state, "last_turn_cache_tokens")
          lastUpdateAt = getJsonInt64(state, "last_update_at")
          lastActiveAt = getJsonInt64(state, "last_active_at")
        except:
          discard

      let active = lastActiveAt > 0 and (nowMs - lastActiveAt) < 120_000
      var questionMs: int64 = 0
      if active and answering and lastPromptAt > 0:
        questionMs = nowMs - lastPromptAt
      elif lastAnswerDurationMs > 0:
        questionMs = lastAnswerDurationMs

      let baseTodayMs =
        getJsonInt64(totals, "today_time_ms")
      let liveToday =
        if active and lastUpdateAt > 0: max(0'i64, nowMs - lastUpdateAt)
        else: 0'i64

      result.add(ClaudeProjectSnapshot(
        name: getJsonString(totals, "project_name", slug),
        active: active,
        answering: active and answering,
        lastActiveAt: lastActiveAt,
        questionMs: questionMs,
        questionStartMs: if active and answering: lastPromptAt else: 0,
        todayMs: baseTodayMs + liveToday,
        sessionTokens: lastTurnTokens,
        sessionCacheTokens: lastTurnCacheTokens,
        todayTokens: getJsonInt64(totals, "today_tokens"),
        todayCacheTokens: getJsonInt64(totals, "today_cache_tokens"),
      ))
    except:
      discard

  result.sort(proc(a, b: ClaudeProjectSnapshot): int =
    result = cmp(b.answering.int, a.answering.int)
    if result != 0: return
    result = cmp(b.active.int, a.active.int)
    if result != 0: return
    result = cmp(b.lastActiveAt, a.lastActiveAt)
    if result != 0: return
    result = cmp(b.todayMs, a.todayMs)
  )
