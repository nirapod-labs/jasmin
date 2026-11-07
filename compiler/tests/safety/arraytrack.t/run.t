With "array_track_max_bytes", the values of the cells of larger arrays are
unknown: a value read from such an array is no longer known to be a valid
index. Initialization and index bounds are still checked.

  $ ../../../jasmin-checksafety lookup.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation

  $ ../../../jasmin-checksafety --config small.json lookup.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "lookup.jazz", line 9 (2-11): in_bound: t[v] (length 128 U8)
  Program is not safe!

  $ ../../../jasmin-checksafety masked.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation

  $ ../../../jasmin-checksafety --config small.json masked.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation

  $ ../../../jasmin-checksafety uninit.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "uninit.jazz", line 8 (2-11): is_init t[i]
  Program is not safe!

  $ ../../../jasmin-checksafety --config small.json uninit.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "uninit.jazz", line 8 (2-11): is_init t[i]
  Program is not safe!
