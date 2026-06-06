## 数据模型定义

type
  ToolType* = enum
    ttClaude, ttCodex, ttDeepSeek

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

  DeepSeekData* = object
    todayCost*: float
    todayTokens*: int64
    cacheHitRate*: float
    balance*: float
    balanceCurrency*: string
    balanceAvailable*: bool
    balanceOk*: bool
    billUpdatedMs*: int64
    weekTokens*: array[7, int64]
