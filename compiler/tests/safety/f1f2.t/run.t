Two pre-existing soundness defects of the checker, each with the program
that shows it. The source semantics is the reference: an execution of the
same body stops where the expectation says the alarm is (the interpreter
copies are in the lab under f1f2/). These tests run on armv8a; their
x86-64 twins are queued in RUNS-LATER.md, since the x86-64 host is
offline and x86-64 checker runs are not made on the Mac in the meantime.

A boolean set from an array cell keeps no fact about it after the cell is
written: b is true, then t[0] becomes 1, the branch is taken in the source
and u[5] is out of bounds.

  $ ../../../jasmin-checksafety --arch=armv8a sym_stale.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_init .*" -e "No Safety Violation"
  line 15
  is_init u[i]
  line 15
  in_bound: u[i] (length 16 U8)

The same through a whole-array copy.

  $ ../../../jasmin-checksafety --arch=armv8a sym_stale_copy.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_init .*" -e "No Safety Violation"
  line 16
  is_init u[i]
  line 16
  in_bound: u[i] (length 16 U8)

The same across widths: b reads one byte of t, the copy writes eight.

  $ ../../../jasmin-checksafety --arch=armv8a sym_stale_wide.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_init .*" -e "No Safety Violation"
  line 15
  is_init u[i]
  line 15
  in_bound: u[i] (length 16 U8)

A write to another array leaves the fact true, and the branch stays dead.

  $ ../../../jasmin-checksafety --arch=armv8a sym_keep.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
