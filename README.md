# AI Usage Monitor

Windows 桌面常驻悬浮窗，用于实时查看 Claude Code CLI 和 Codex CLI 的状态、单次 Token、缓存 Token、今日累计 Token。

项目重点是数据准确、稳定、低资源占用。当前实现使用 Nim、Win32 API、GDI、ReadDirectoryChangesW 和轻量 JSON 字段读取，不依赖 Electron、Python、Node、Chromium、WebView、SQLite。

## 功能

- Claude / Codex 双区域显示
- 执行状态、单次耗时、单次 Token、单次缓存、今日累计
- 运行中 Token / 缓存以三点动画显示，结束后显示最终数值
- 无边框、始终置顶、可拖动、透明度设置
- 系统托盘显示 / 隐藏 / 退出
- 弹窗模式和任务栏悬浮模式切换
- 位置记忆、配置热更新
- 文件变化驱动刷新，空闲低频工作集回收

## 数据来源

只读取 CLI 已存在的本地文件。不使用注入、Hook、抓包、代理、反编译、进程内存读取。

### Claude Code

读取目录：

```text
%USERPROFILE%\.claude\project-time\
```

使用文件：

- `<project>.json`
- `<project>-state.json`

主要字段：

- `answering`
- `last_prompt_at`
- `last_answer_duration_ms`
- `last_turn_tokens`
- `last_turn_cache_tokens`
- `today_tokens`
- `today_cache_tokens`

### Codex

读取目录：

```text
%USERPROFILE%\.codex\sessions\<YYYY>\<MM>\<DD>\
```

使用文件：

- `rollout-*.jsonl`

主要事件：

- `user_message`
- `agent_message` + `phase=final_answer`
- `token_count`

## 项目结构

```text
ai-usage-monitor/
├─ src/
│  ├─ main.nim              # 入口和 Win32 消息循环
│  ├─ ui.nim                # Win32 GDI 绘制、窗口交互、配置热更新
│  ├─ monitor.nim           # 数据刷新、文件通知、跨日重置
│  ├─ models.nim            # 数据模型
│  ├─ config.nim            # config.json 读取和保存
│  ├─ storage.nim           # stats.json 读取和保存
│  ├─ filewatch.nim         # ReadDirectoryChangesW 单线程文件通知
│  ├─ processutil.nim       # 进程名存在性检查
│  ├─ memoryutil.nim        # 空闲工作集回收
│  ├─ jsonlite.nim          # 轻量 JSON 字段读取
│  ├─ timeutil.nim          # 轻量时间和日期工具
│  ├─ tray.nim              # 系统托盘
│  └─ sources/
│     ├─ claude.nim         # Claude 数据源
│     └─ codex.nim          # Codex 数据源
├─ build/
│  └─ build.bat             # Release 构建脚本
├─ config/
│  └─ config.example.json   # 配置示例
├─ dist/                    # 本地构建产物，Git 忽略
├─ ai_usage_monitor.nimble
├─ README.md
├─ LICENSE
├─ .gitignore
└─ .gitattributes
```

## 构建

依赖：

- Nim 2.0+
- winim 3.9+
- MinGW-w64

Windows 下可用 winget 安装：

```bat
winget install nim.nim
winget install BrechtSanders.WinLibs.POSIX.UCRT
nimble install winim -y
```

构建：

```bat
build\build.bat
```

输出：

```text
dist\ai-usage-monitor.exe
```

等价 Release 参数：

```bat
nim c -d:release --opt:size --mm:arc --app:gui --stackTrace:off --lineTrace:off --assertions:off --panics:on -d:danger -d:strip -o:dist\ai-usage-monitor.exe src/main.nim
```

## 配置

运行时读取当前工作目录下的 `config.json`。如果不存在，会使用默认值并在退出时保存。

示例见：

```text
config\config.example.json
```

字段：

```json
{
  "refreshInterval": 1000,
  "alwaysOnTop": true,
  "clickThrough": false,
  "opacity": 0.85,
  "windowX": -1,
  "windowY": -1,
  "compactWindowX": -1,
  "codexSessionDir": ""
}
```

## 资源占用

当前 Release 构建约 190KB。空闲时会低频回收工作集，常见工作集在 9MB 左右波动；私有内存约 11MB 到 13MB。

## 限制

- 只支持 Windows。
- 依赖 Claude Code / Codex 本地文件格式保持兼容。
- 不实现费用、本月统计、请求次数、平均响应时间等预留字段。

## License

MIT
