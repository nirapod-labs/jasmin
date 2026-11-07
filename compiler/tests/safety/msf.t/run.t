A misspeculation flag has no value for the checker. No memory access
depends on a flag in the source semantics, since #protect and #protect_ptr
return their first operand, so a flag used as data, here as an index, is
unknown and the read is rejected, though the flag is 0 after #init_msf.

  $ ../../../jasmin-checksafety flag_index.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "flag_index.jazz", line 11 (2-12): in_bound: a[ms] (length 16 U8)
  Program is not safe!
  $ ../../../jasmin-checksafety --arch=armv8a flag_index.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "flag_index.jazz", line 11 (2-12): in_bound: a[ms] (length 16 U8)
  Program is not safe!
