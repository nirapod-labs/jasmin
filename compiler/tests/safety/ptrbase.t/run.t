An access through a pointer moved by an offset, [p = p + e], keeps the region
of [p] alone, whatever the variables of [e] point to, with its offset moved
by [e].

  $ ../../../jasmin-checksafety moved.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a moved.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation

The range of [in] is bounded by [inlen].

  $ ../../../jasmin-checksafety moved.jazz 2>&1 | grep -o -e "inv_inlen ≥ mem_in" -e "mem_in ≤ [^,}]*"
  inv_inlen ≥ mem_in
  $ ../../../jasmin-checksafety --arch=armv8a moved.jazz 2>&1 | grep -o -e "inv_inlen ≥ mem_in" -e "mem_in ≤ [^,}]*"
  inv_inlen ≥ mem_in

One byte too many: the range of [in] exceeds [inlen] by one. Since [inlen]
may be 2^64 - 1, the range reaches 2^64 bytes, and the run is rejected for
it; with a smaller [inlen] only the comparison of the range with the
caller's buffer would reject it.

  $ ../../../jasmin-checksafety moved_wide.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
  Program is not safe!
  $ ../../../jasmin-checksafety moved_wide.jazz 2>&1 | grep -o -e "inv_inlen ≥ mem_in" -e "mem_in ≤ [^,}]*"
  mem_in ≤ inv_inlen + 1

Two regions: no region is chosen.

  $ ../../../jasmin-checksafety moved_two.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "moved_two.jazz", line 13 (2-10): is_valid q u64
  Program is not safe!

The length as the base: the read is relative to the region of [inlen], at an
offset as large as the value of [in], so the range of [inlen] is larger than
the address space.

  $ ../../../jasmin-checksafety moved_commuted.jazz 2>&1 | grep -e Violation -e line -e safe -e bounded -e "mem_in:" -e "mem_inlen:"
  *** Possible Safety Violation(s):
    moved_commuted return: bounded memory range of inlen
    mem_in: [0; 0]
    mem_inlen: [0; 18446744073709551623]
  Program is not safe!

An unconstrained offset: the range of [in] is larger than the address space.

  $ ../../../jasmin-checksafety moved_other.jazz 2>&1 | grep -e Violation -e line -e safe -e bounded -e "mem_in:"
  *** Possible Safety Violation(s):
    moved_other return: bounded memory range of in
    mem_in: [0; 18446744073709551623]
  Program is not safe!

The destination on the right of the addition.

  $ ../../../jasmin-checksafety moved_self.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "moved_self.jazz", line 10 (2-10): is_valid q u64
  Program is not safe!

An offset the numerical domain does not model is unknown.

  $ ../../../jasmin-checksafety moved_xor.jazz 2>&1 | grep -e Violation -e line -e safe -e bounded -e "mem_in:" -e rror
  *** Possible Safety Violation(s):
    moved_xor return: bounded memory range of in
    mem_in: [-1/0; inf]
  Program is not safe!

A length as the base, moved by a bounded value: the read is relative to the
region of [inlen]. The verdict holds only under a range of [inlen] that no
caller passing a length meets, and only a comparison of the ranges with the
caller's buffers rejects it.

  $ ../../../jasmin-checksafety moved_lenbase.jazz 2>&1 | grep -e Violation -e line -e safe -e bounded -e "mem_in:" -e "mem_inlen:"
  *** No Safety Violation
    mem_in: [0; 0]
    mem_inlen: [0; 15]
  $ ../../../jasmin-checksafety --arch=armv8a moved_lenbase.jazz 2>&1 | grep -e Violation -e line -e safe -e bounded -e "mem_in:" -e "mem_inlen:"
  *** No Safety Violation
    mem_in: [0; 0]
    mem_inlen: [0; 15]
