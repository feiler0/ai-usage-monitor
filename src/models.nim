## 数据模型定义

type
  ToolType* = enum
    ttClaude, ttCodex

  ToolStatus* = enum
    tsIdle, tsRunning

  MonitorData* = object
    tool*: ToolType
    name*: string
    status*: ToolStatus
    sessionDurationSec*: int64
    sessionTokens*: int64
    sessionCacheTokens*: int64
    todayTokens*: int64
    todayCacheTokens*: int64
    answering*: bool
    turnStartMs*: int64

  AppConfig* = object
    refreshInterval*: int
    alwaysOnTop*: bool
    respectFullscreenWindows*: bool
    clickThrough*: bool
    opacity*: float
    windowX*: int
    windowY*: int
    compactWindowX*: int
    codexSessionDir*: string

  AppStats* = object
    claudeTodayTokens*: int64
    claudeTodayCacheTokens*: int64
    codexTodayTokens*: int64
    codexTodayCacheTokens*: int64
    lastDate*: string

  ClaudeProjectSnapshot* = object
    name*: string
    active*: bool
    answering*: bool
    lastActiveAt*: int64
    questionMs*: int64
    questionStartMs*: int64
    todayMs*: int64
    sessionTokens*: int64
    sessionCacheTokens*: int64
    todayTokens*: int64
    todayCacheTokens*: int64

  CodexTokenInfo* = object
    cachedInputTokens*: int64
    totalTokens*: int64
    lastCachedInputTokens*: int64
    lastTotalTokens*: int64

  CodexTurnState* = object
    answering*: bool
    startMs*: int64
    lastEventMs*: int64
    durationSec*: int64
