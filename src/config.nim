## 配置加载/保存

import std/os
import models
import jsonlite

const
  DefaultConfigPath* = "config.json"
  DefaultRefreshInterval = 1000
  DefaultOpacity = 0.85
  MinRefreshInterval = 250
  MaxRefreshInterval = 60_000

proc normalize(config: var AppConfig) =
  if config.refreshInterval < MinRefreshInterval:
    config.refreshInterval = MinRefreshInterval
  if config.refreshInterval > MaxRefreshInterval:
    config.refreshInterval = MaxRefreshInterval
  if config.opacity < 0.1:
    config.opacity = 0.1
  if config.opacity > 1.0:
    config.opacity = 1.0

proc defaultConfig*(): AppConfig =
  result = AppConfig(
    refreshInterval: DefaultRefreshInterval,
    alwaysOnTop: true,
    clickThrough: false,
    opacity: DefaultOpacity,
    windowX: -1,
    windowY: -1,
    compactWindowX: -1,
    codexSessionDir: "",
  )

proc loadConfig*(path: string = DefaultConfigPath): AppConfig =
  result = defaultConfig()
  if not fileExists(path):
    return result
  try:
    let content = readFile(path)
    if content.len == 0:
      return result
    result.refreshInterval = getJsonInt(content, "refreshInterval", result.refreshInterval)
    result.alwaysOnTop = getJsonBool(content, "alwaysOnTop", result.alwaysOnTop)
    result.clickThrough = getJsonBool(content, "clickThrough", result.clickThrough)
    result.opacity = getJsonFloat(content, "opacity", result.opacity)
    result.windowX = getJsonInt(content, "windowX", result.windowX)
    result.windowY = getJsonInt(content, "windowY", result.windowY)
    result.compactWindowX = getJsonInt(content, "compactWindowX", result.compactWindowX)
    result.codexSessionDir = getJsonString(content, "codexSessionDir", result.codexSessionDir)
  except:
    discard
  normalize(result)

proc saveConfig*(config: AppConfig, path: string = DefaultConfigPath) =
  var cfg = config
  normalize(cfg)
  let content = "{\n" &
    "  \"refreshInterval\": " & $cfg.refreshInterval & ",\n" &
    "  \"alwaysOnTop\": " & $cfg.alwaysOnTop & ",\n" &
    "  \"clickThrough\": " & $cfg.clickThrough & ",\n" &
    "  \"opacity\": " & $cfg.opacity & ",\n" &
    "  \"windowX\": " & $cfg.windowX & ",\n" &
    "  \"windowY\": " & $cfg.windowY & ",\n" &
    "  \"compactWindowX\": " & $cfg.compactWindowX & ",\n" &
    "  \"codexSessionDir\": \"" & jsonEscape(cfg.codexSessionDir) & "\"\n" &
    "}"
  try:
    writeFile(path, content)
  except:
    discard
