P4a: a pointer read at pointer width from a cell of an export table
argument points to the region of that cell's entry value, mem_in.k, at
offset 0. A copy of the table, a sub-array of it, a parameter bound to it,
#protect_ptr and #copy keep the cells' regions. Every other way an array
can change clears them.

The commands below pin armv8a; the x86-64 twins are queued in
RUNS-LATER.md, because the x86-64 host is offline and x86-64 checker runs
are not made on the Mac in the meantime.

A table, whole and through calls, keeps its lanes.

  $ ../../../jasmin-checksafety --arch=armv8a lanes.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_call.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_sub.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_moved.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_two.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_copy_ok.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_swap_ok.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_protect_ptr.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_direct.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation


The packing ties each lane's range to the length: the printed relations
are what ranges.py compares with the export's contract.

  $ ../../../jasmin-checksafety --arch=armv8a lanes.jazz 2>&1 | grep -o -e "inv_len ≥ mem_in\.[0-9]"
  inv_len ≥ mem_in.0
  inv_len ≥ mem_in.1
  $ ../../../jasmin-checksafety --arch=armv8a lanes_sub.jazz 2>&1 | grep -o -e "inv_len ≥ mem_in\.[0-9]"
  inv_len ≥ mem_in.1
  $ ../../../jasmin-checksafety --arch=armv8a lanes_copy_ok.jazz 2>&1 | grep -o -e "inv_len ≥ mem_in\.[0-9]"
  inv_len ≥ mem_in.1

A callee without memory access that receives the table is analysed
directly rather than from top, which would lose the cells' regions (it is
the only case where the strategy may depend on the provenance; a callee
already on the call stack keeps the top strategy, so a recursive function
still terminates).

  $ ../../../jasmin-checksafety --arch=armv8a --config=calltop.json lanes_calltop.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation

A table that changes before the read gives no region: a #swap with a
written array, a cell written by a call, a cell written directly, one byte
written, a write through a #copy into a sub-array, a run-time index, a
whole-array copy that was written, #randombytes, ArrayInit, one path of a
join, a second iteration of a loop, a callee that writes and returns the
table.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_swap.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 11
  is_init in[0]
  line 15
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_twice.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 10
  is_valid vp +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_result_sub.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 17
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_written.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 11
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_written_byte.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_written_index.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 12
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_copy_op.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_copy.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 15
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_random.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 11
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_arrinit.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 7
  is_init in[0]
  line 11
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_join.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_loop_overwrite.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 10
  is_valid p u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_returned.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 18
  is_valid p +64u i u8

A read that is not a constant pointer-width cell of a table argument gives
no region: a straddling word, a narrower read and a cast, a run-time cell
index, a table in memory, a local table built from arguments.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_unaligned.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 10
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_narrow.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 12
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_index.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 12
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_load.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 10
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_local.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_valid p +64u i u8

A sub-array copy, a write between #spill and #unspill, and #protect_ptr
from a written table all clear the binding; a global table is not an
export argument, so no region exists for its cells.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_sub_write.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 13
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_spill_write.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 14
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_protect_ptr_written.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 16
  is_valid p +64u i u8
  $ ../../../jasmin-checksafety --arch=armv8a lanes_global.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 12
  is_valid p +64u i u8

The vector kernels' shape reloads both lane pointers at the top of every
iteration and moves them by the block offset. The packing ties the lane
pointers to the table, but the offset of the block is not itself in the
loop's relational closure, so the ranges are not tied to the iteration
count and the bounded-range check rejects them. This is the precision gap
recorded in P4-DESIGN 6.4; the library's own multi-way update exports use
the same shape and are expected to end here until the offset is packed.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_while.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  bounded memory range of in.0
  bounded memory range of in.1

A callee that reads past its table of one cell reports the access and the
unknown pointer.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_oob.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  line 7
  is_init t[j]
  line 7
  in_bound: t[j] (length 8 U8)
  line 11
  is_valid p +64u i u8

One byte past a lane of unbounded len makes the lane's range as large as
the address space, which the bounded-range check rejects. With len below
2^61 the checker reports no violation and the comparison with the
caller's buffer is what rejects it (ranges.py). A pointer moved between
two lanes by their difference gets the first lane's region with an
unbounded offset.

  $ ../../../jasmin-checksafety --arch=armv8a lanes_wide.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  bounded memory range of in.0
  $ ../../../jasmin-checksafety --arch=armv8a lanes_wide_small.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  No Safety Violation
  $ ../../../jasmin-checksafety --arch=armv8a lanes_cross.jazz 2>&1 | grep -o -e "line [0-9]*" -e "in_bound: .*" -e "is_valid .*" -e "bounded memory range of .*" -e "is_init .*" -e "No Safety Violation"
  bounded memory range of in.0
