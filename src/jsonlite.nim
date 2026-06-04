import std/strutils

proc findValueStart(s, key: string): int =
  let marker = "\"" & key & "\""
  let keyPos = s.find(marker)
  if keyPos < 0:
    return -1
  let colon = s.find(':', keyPos + marker.len)
  if colon < 0:
    return -1
  result = colon + 1
  while result < s.len and s[result] in {' ', '\t', '\r', '\n'}:
    inc result

proc jsonEscape*(value: string): string =
  for ch in value:
    case ch
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(ch)

proc jsonUnescape(value: string): string =
  var i = 0
  while i < value.len:
    if value[i] == '\\' and i + 1 < value.len:
      inc i
      case value[i]
      of '\\': result.add('\\')
      of '"': result.add('"')
      of 'n': result.add('\n')
      of 'r': result.add('\r')
      of 't': result.add('\t')
      else: result.add(value[i])
    else:
      result.add(value[i])
    inc i

proc getJsonString*(s, key: string, default = ""): string =
  var pos = findValueStart(s, key)
  if pos < 0 or pos >= s.len or s[pos] != '"':
    return default
  inc pos
  var raw = ""
  var escaped = false
  while pos < s.len:
    let ch = s[pos]
    if escaped:
      raw.add('\\')
      raw.add(ch)
      escaped = false
    elif ch == '\\':
      escaped = true
    elif ch == '"':
      return jsonUnescape(raw)
    else:
      raw.add(ch)
    inc pos
  default

proc getJsonBool*(s, key: string, default = false): bool =
  let pos = findValueStart(s, key)
  if pos < 0:
    return default
  if s.continuesWith("true", pos):
    return true
  if s.continuesWith("false", pos):
    return false
  default

proc getJsonInt64*(s, key: string, default: int64 = 0): int64 =
  var pos = findValueStart(s, key)
  if pos < 0:
    return default
  var sign: int64 = 1
  if pos < s.len and s[pos] == '-':
    sign = -1
    inc pos
  var seen = false
  while pos < s.len and s[pos] in {'0'..'9'}:
    seen = true
    result = result * 10 + int64(ord(s[pos]) - ord('0'))
    inc pos
  if seen:
    result *= sign
  else:
    result = default

proc getJsonInt*(s, key: string, default = 0): int =
  int(getJsonInt64(s, key, int64(default)))

proc getJsonFloat*(s, key: string, default = 0.0): float =
  var pos = findValueStart(s, key)
  if pos < 0:
    return default
  let start = pos
  while pos < s.len and s[pos] in {'-', '+', '.', '0'..'9', 'e', 'E'}:
    inc pos
  try:
    result = parseFloat(s[start ..< pos])
  except:
    result = default
