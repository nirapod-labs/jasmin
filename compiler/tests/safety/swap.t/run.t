The results of an instruction are evaluated from its arguments before any
lvalue is written, and each lvalue is located in the state the writes
before it left. These are the two shapes the review of the operator fix
asked to pin (REVIEW-P3R2-PATCHES 3.4), on armv8a; their x86-64 twins are
queued in RUNS-LATER.md, since the x86-64 host is offline and x86-64
checker runs are not made on the Mac.

A sub-array result of #swap that reads no earlier lvalue keeps its value:
#swap(b, t[1 : 1]) returns (t[1 : 1], b), so both the second result and a
are written before they are read.

  $ ../../../jasmin-checksafety --arch=armv8a swap_sub.jazz 2>&1 | grep -e Violation -e "line [0-9]" -e safe
  *** No Safety Violation

#swap(a, b) returns (b, a): the sub-array t[0 : 1] receives the old a,
which was never written, so the read of t[0] is a read of an
uninitialised cell and must alarm.

  $ ../../../jasmin-checksafety --arch=armv8a swap_sub_init.jazz 2>&1 | grep -e Violation -e "line [0-9]" -e safe
  *** Possible Safety Violation(s):
    "swap_sub_init.jazz", line 13 (2-11): is_init t[0]
  Program is not safe!

The first lvalue writes t at an unknown index, 0 or 1. The index of the
second lvalue reads t[0], which that write changes when the index is 0;
the pending result is forgotten before the index is read, so the index is
unknown and the access must alarm.

  $ ../../../jasmin-checksafety --arch=armv8a swap_pending.jazz 2>&1 | grep -e Violation -e "line [0-9]" -e safe
  *** Possible Safety Violation(s):
    "swap_pending.jazz", line 16 (2-30): in_bound: u[t[0]] (length 16 U8)
  Program is not safe!
