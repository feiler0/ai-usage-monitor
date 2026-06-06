## 文件监控模块

import std/os
import models
import filewatch
import sources/[claude, codex, deepseek]
import processutil
import timeutil
import memoryutil

type
  Monitor* = ref object
    config*: AppConfig
    stats*: AppStats
    claudeData*: MonitorData
    codexData*: MonitorData
    deepseekData*: DeepSeekData
    claudeWatcher*: DirectoryWatcher
    codexWatcher*: DirectoryWatcher
    deepseekWatcher*: DirectoryWatcher
    latestCodexJsonl*: string
    lastCodexAggregateMs*: int64
    lastDeepSeekBalanceMs*: int64
    claudeDirty*: bool
    codexDirty*: bool
    deepseekDirty*: bool

const
  CodexAggregateFallbackMs = 3000'i64

proc clearTurn(data: var MonitorData) =
  data.status = tsIdle
  data.answering = false
  data.sessionDurationSec = 0
  data.sessionTokens = 0
  data.sessionCacheTokens = 0
  data.turnStartMs = 0

proc clearAll(data: var MonitorData) =
  clearTurn(data)
  data.todayTokens = 0
  data.todayCacheTokens = 0

proc initMonitor*(config: AppConfig, stats: AppStats): Monitor =
  result = Monitor(
    config: config,
    stats: stats,
    claudeData: MonitorData(tool: ttClaude, name: "Claude", status: tsIdle),
    codexData: MonitorData(tool: ttCodex, name: "Codex", status: tsIdle),
    claudeDirty: true,
    codexDirty: true,
    deepseekDirty: true,
  )
  result.claudeWatcher = initDirectoryWatcher(getProjectTimeDir())
  let codexRoot =
    if config.codexSessionDir.len > 0: config.codexSessionDir
    else: getCodexSessionsRoot()
  result.codexWatcher = initDirectoryWatcher(codexRoot)
  result.deepseekWatcher = initDirectoryWatcher(getHomeDir() / ".reasonix", recursive = false)

proc resetDailyIfNeeded(m: Monitor) =
  let today = todayKey()
  if m.stats.lastDate == today:
    return
  m.stats.lastDate = today
  m.stats.claudeTodayTokens = 0
  m.stats.claudeTodayCacheTokens = 0
  m.stats.codexTodayTokens = 0
  m.stats.codexTodayCacheTokens = 0
  m.claudeData.todayTokens = 0
  m.claudeData.todayCacheTokens = 0
  m.codexData.todayTokens = 0
  m.codexData.todayCacheTokens = 0
  m.claudeDirty = true
  m.codexDirty = true

proc refreshClaudeData*(m: Monitor) =
  let projectTimeDir = getProjectTimeDir()

  if m.claudeDirty:
    let projects = parseClaudeProjectSnapshots(projectTimeDir)
    m.claudeDirty = false
    if projects.len > 0:
      let p = projects[0]
      m.claudeData.status = if p.answering: tsRunning else: tsIdle
      m.claudeData.answering = p.answering
      m.claudeData.turnStartMs = p.questionStartMs
      m.claudeData.sessionDurationSec = max(0'i64, p.questionMs div 1000)
      m.claudeData.sessionTokens = p.sessionTokens
      m.claudeData.sessionCacheTokens = p.sessionCacheTokens
      m.claudeData.todayTokens = p.todayTokens
      m.claudeData.todayCacheTokens = p.todayCacheTokens
    else:
      clearAll(m.claudeData)

  if m.claudeData.status == tsRunning and m.claudeData.turnStartMs > 0:
    let nowMs = nowUnixMs()
    m.claudeData.sessionDurationSec = max(0'i64, (nowMs - m.claudeData.turnStartMs) div 1000)

  m.stats.claudeTodayTokens = m.claudeData.todayTokens
  m.stats.claudeTodayCacheTokens = m.claudeData.todayCacheTokens

proc refreshCodexData*(m: Monitor) =
  let sessionsRoot =
    if m.config.codexSessionDir.len > 0: m.config.codexSessionDir
    else: getCodexSessionsRoot()

  let wasCodexDirty = m.codexDirty or m.latestCodexJsonl.len == 0
  if wasCodexDirty:
    m.latestCodexJsonl = findLatestCodexJsonl(sessionsRoot)
    m.codexDirty = false

  let latestJsonl = m.latestCodexJsonl

  if latestJsonl.len > 0:
    if wasCodexDirty:
      let info = parseCodexTokenCount(latestJsonl)
      let turn = parseCodexTurnState(latestJsonl)
      let codexAlive = processNameExists("Codex.exe") or processNameExists("codex.exe")

      m.codexData.sessionTokens =
        if info.lastTotalTokens > 0: info.lastTotalTokens else: info.totalTokens
      m.codexData.sessionCacheTokens =
        if info.lastCachedInputTokens > 0: info.lastCachedInputTokens else: info.cachedInputTokens
      m.codexData.turnStartMs = turn.startMs
      m.codexData.sessionDurationSec = turn.durationSec
      if turn.answering and codexAlive:
        m.codexData.status = tsRunning
        m.codexData.answering = true
      else:
        m.codexData.status = tsIdle
        m.codexData.answering = false
        if turn.answering and turn.lastEventMs > turn.startMs:
          m.codexData.sessionDurationSec = (turn.lastEventMs - turn.startMs) div 1000

    if m.codexData.status == tsRunning and m.codexData.turnStartMs > 0:
      let nowMs = nowUnixMs()
      m.codexData.sessionDurationSec = max(0'i64, (nowMs - m.codexData.turnStartMs) div 1000)
  else:
    clearTurn(m.codexData)

  let nowMs = nowUnixMs()
  if wasCodexDirty or m.codexData.todayTokens == 0 or
      nowMs - m.lastCodexAggregateMs >= CodexAggregateFallbackMs:
    let todayTokens = aggregateTodayCodexTokens(sessionsRoot)
    m.codexData.todayTokens = todayTokens.tokens
    m.codexData.todayCacheTokens = todayTokens.cache
    m.lastCodexAggregateMs = nowMs
  m.stats.codexTodayTokens = m.codexData.todayTokens
  m.stats.codexTodayCacheTokens = m.codexData.todayCacheTokens

proc refreshDeepSeekData*(m: Monitor) =
  let nowMs = nowUnixMs()
  if m.deepseekDirty:
    let previousBalance = m.deepseekData.balance
    let previousCurrency = m.deepseekData.balanceCurrency
    let previousAvailable = m.deepseekData.balanceAvailable
    let previousOk = m.deepseekData.balanceOk
    m.deepseekData = parseUsageStats()
    m.deepseekData.balance = previousBalance
    m.deepseekData.balanceCurrency = previousCurrency
    m.deepseekData.balanceAvailable = previousAvailable
    m.deepseekData.balanceOk = previousOk
    m.deepseekDirty = false

  if nowMs - m.lastDeepSeekBalanceMs >= BalanceRefreshMs or m.lastDeepSeekBalanceMs == 0:
    refreshBalance(m.deepseekData)
    m.lastDeepSeekBalanceMs = nowMs
    trimWorkingSet()

proc refreshAll*(m: Monitor) =
  resetDailyIfNeeded(m)
  if changed(m.claudeWatcher):
    m.claudeDirty = true
  if changed(m.codexWatcher):
    m.codexDirty = true
  if changed(m.deepseekWatcher):
    m.deepseekDirty = true
  refreshClaudeData(m)
  refreshCodexData(m)
  refreshDeepSeekData(m)

proc closeMonitor*(m: Monitor) =
  close(m.claudeWatcher)
  close(m.codexWatcher)
  close(m.deepseekWatcher)

proc applyConfig*(m: Monitor, config: AppConfig) =
  let oldCodexRoot =
    if m.config.codexSessionDir.len > 0: m.config.codexSessionDir
    else: getCodexSessionsRoot()
  let newCodexRoot =
    if config.codexSessionDir.len > 0: config.codexSessionDir
    else: getCodexSessionsRoot()

  m.config = config
  if oldCodexRoot != newCodexRoot:
    close(m.codexWatcher)
    m.codexWatcher = initDirectoryWatcher(newCodexRoot)
    m.latestCodexJsonl = ""
    m.codexDirty = true
