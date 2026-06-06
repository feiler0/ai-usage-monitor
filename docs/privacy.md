# Privacy

AI Usage Monitor is designed as a local-only desktop monitor.

- It does not upload Claude, Codex, or Reasonix session files.
- It does not read process memory.
- It does not capture network traffic.
- It does not run a proxy or man-in-the-middle service.
- It does not inject DLLs or hook APIs.
- It does not modify CLI/client source code.
- DeepSeek API keys are read only to request the official balance endpoint.
- API keys are not displayed in the UI and are not written to logs.

The only network request currently used by the app is:

```text
GET https://api.deepseek.com/user/balance
```

All usage history shown by the app comes from local files that already exist on the user's machine.

