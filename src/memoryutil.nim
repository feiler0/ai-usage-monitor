## Current-process memory helpers

when defined(windows):
  import winim/lean

  proc trimWorkingSet*() =
    discard SetProcessWorkingSetSize(GetCurrentProcess(), SIZE_T(-1), SIZE_T(-1))
else:
  proc trimWorkingSet*() = discard
