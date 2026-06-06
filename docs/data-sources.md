# Data Sources

AI Usage Monitor only reads local files or official provider endpoints that are already available to the user. It does not inject into processes, hook APIs, read process memory, capture packets, proxy traffic, reverse engineer clients, or modify CLI source code.

## Claude Code

Source directory:

```text
%USERPROFILE%\.claude\project-time\
```

Files:

- `<project>.json`
- `<project>-state.json`

Used fields:

- `answering`
- `last_prompt_at`
- `last_answer_duration_ms`
- `last_turn_tokens`
- `last_turn_cache_tokens`
- `today_tokens`
- `today_cache_tokens`

Reliable metrics:

- current active/answering state
- current turn duration
- current turn token/cache totals after the local state file writes them
- daily token/cache totals from Claude's local project-time data

## Codex

Source directory:

```text
%USERPROFILE%\.codex\sessions\<YYYY>\<MM>\<DD>\
```

Files:

- `rollout-*.jsonl`

Used events:

- `event_msg` with `user_message`
- `event_msg` with `agent_message` and `phase=final_answer`
- `token_count`

Reliable metrics:

- current turn duration based on the latest user and final-answer timestamps
- current/last turn token totals from `last_token_usage`
- daily token/cache totals from same-day `token_count` events

Limitations:

- process state is used only to stop an active timer when the Codex process exits
- no fee calculation is performed for Codex

## DeepSeek / Reasonix

Billing source:

```text
%USERPROFILE%\.reasonix\usage.jsonl
```

Used fields:

- `ts`
- `costUsd`
- `promptTokens`
- `completionTokens`
- `cacheHitTokens`
- `cacheMissTokens`

Balance source:

```text
GET https://api.deepseek.com/user/balance
```

The API key is read from local configuration or `DEEPSEEK_API_KEY`. It is not displayed or written to logs.

Reasonix session source:

```text
%APPDATA%\reasonix\sessions\
```

This directory is used only to detect whether a newer Reasonix session exists after the last billing record. If a session file is newer than `usage.jsonl`, the UI marks the billing data as `未落账`.

Important limitation:

Reasonix session JSONL files are not treated as a billing source unless they contain verified structured usage fields. Conversation text is never used to estimate cost, token totals, or cache hit rate.

