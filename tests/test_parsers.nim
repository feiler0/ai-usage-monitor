import std/[os, unittest]

import ../src/sources/claude
import ../src/sources/codex
import ../src/sources/deepseek

const FixtureRoot = currentSourcePath().parentDir / "fixtures"

suite "parser fixtures":
  test "Claude project-time fixture":
    let snapshots = parseClaudeProjectSnapshots(FixtureRoot / "claude")
    check snapshots.len == 1
    check snapshots[0].name == "sample"
    check snapshots[0].sessionTokens == 1234
    check snapshots[0].sessionCacheTokens == 456
    check snapshots[0].todayTokens == 34567
    check snapshots[0].todayCacheTokens == 8901

  test "Codex rollout fixture":
    let path = FixtureRoot / "codex" / "rollout-sample.jsonl"
    let info = parseCodexTokenCount(path)
    check info.lastTotalTokens == 1200
    check info.lastCachedInputTokens == 200
    check info.totalTokens == 5000
    check info.cachedInputTokens == 900
    let turn = parseCodexTurnState(path)
    check turn.answering == false
    check turn.durationSec == 20

  test "DeepSeek usage fixture":
    let data = parseUsageStats(FixtureRoot / "deepseek" / "usage.jsonl")
    check data.hasBillingData == true
    check data.todayTokens == 4500
    check data.todayCost == 1.0
    check data.cacheHitRate > 24.9
    check data.cacheHitRate < 25.1

  test "DeepSeek missing usage fixture":
    let data = parseUsageStats(FixtureRoot / "deepseek" / "missing.jsonl")
    check data.hasBillingData == false
    check data.billUpdatedMs == 0
    check data.todayTokens == 0
