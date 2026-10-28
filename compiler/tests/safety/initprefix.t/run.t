P3 (a): the initialised prefix of an array. A local array written at
run-time indices has its written bytes counted from offset 0 in a ghost
dimension; a write contiguous with the prefix extends it (T1), a read
covered by it is accepted (T2), a whole-array copy keeps the source's
prefix clamped (T4), and every operation that can lower it goes through
`lower_init`.

These commands pin armv8a; the x86-64 twins are queued in RUNS-LATER.md.
Expected outputs were written from the transfer functions before the
first run.

The fill shape of the one-shot exports: words, bytes, then zeros to the
block end, then a word read of the block.

  $ ../../../jasmin-checksafety --arch=armv8a fillzero.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

The same shape with the library's fill function called from the export.

  $ ../../../jasmin-checksafety --arch=armv8a probe_fill.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

One unwritten byte: the prefix stops before it and the read of the first
word is not covered. The same for a missing zero loop, a copy that starts
at 4, a whole-array copy from an unwritten array, and a descending fill
(the documented precision limit of the abstraction).

  $ ../../../jasmin-checksafety --arch=armv8a gap.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 15
  is_init buf[:u64 0]
  $ ../../../jasmin-checksafety --arch=armv8a short.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 9
  line 12
  is_init buf[:u64 0]
  $ ../../../jasmin-checksafety --arch=armv8a start4.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 14
  is_init buf[:u64 0]
  $ ../../../jasmin-checksafety --arch=armv8a reset.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 15
  is_init buf[:u64 0]
  $ ../../../jasmin-checksafety --arch=armv8a down.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 14
  is_init buf[:u64 0]

The return meet of a second call to a function whose local is written on
one path only must not become bottom: the read inside the second call and
the read of the export's own unwritten local both alarm.

  $ ../../../jasmin-checksafety --arch=armv8a twice_after.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_init t[0]
  line 26
  is_init s[0]

A sub-array result of #swap that receives an unwritten array cuts the
prefix of the filled array.

  $ ../../../jasmin-checksafety --arch=armv8a swap_sub.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_init t[0]

A filled array passed through #protect_ptr to itself keeps its prefix.

  $ ../../../jasmin-checksafety --arch=armv8a protect_self.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

The multi-way fill shape: two 64-byte lanes of one buffer, each filled by a
callee that receives the lane as a sub-array, then a read of each lane.

  $ ../../../jasmin-checksafety --arch=armv8a lane.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

A callee without memory access that only reads a written table, called in a
loop under CallTopHeuristic, reuses its summary without crashing.

  $ ../../../jasmin-checksafety --arch=armv8a --config=calltop.json calltop_reuse.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

The same shape with a fill that writes only 32 of the 64 bytes: the read of
byte 32 of a lane must alarm.

  $ ../../../jasmin-checksafety --arch=armv8a lane_short.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 19
  is_init buf[32]

A full lane copied over the next one keeps both prefixes; with only 32 bytes
written in lane 0, the copy leaves lane 1 uninitialised at byte 64.

  $ ../../../jasmin-checksafety --arch=armv8a copy_lane.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

  $ ../../../jasmin-checksafety --arch=armv8a copy_lane_short.jazz 2>&1 | grep -o -e "line [0-9]*" -e "is_init .*" -e "No Safety Violation"
  line 11
  is_init buf[64]
