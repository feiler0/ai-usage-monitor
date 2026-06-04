when defined(windows):
  import winim/lean

  proc trimWorkingSet*() =
    discard SetProcessWorkingSetSize(
      GetCurrentProcess(),
      cast[SIZE_T](-1),
      cast[SIZE_T](-1)
    )
else:
  proc trimWorkingSet*() = discard
