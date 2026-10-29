The loop in sum reads p[0 .. n-1] with n <= 8. Kept relational, its counter
bounds the memory range to 64 bytes. With "relational_loop_vars" false, the
counter loses its relation to n and the range is much wider; naming sum in
"relational_loop_vars_in" restores the bound for that function only.

  $ ../../../jasmin-checksafety scan.jazz 2>&1 | grep -e Violation -e "mem_p:"
  *** No Safety Violation
    mem_p: [0; 64]

  $ ../../../jasmin-checksafety --config none.json scan.jazz 2>&1 | grep -e Violation -e "mem_p:"
  *** No Safety Violation
    mem_p: [0; 65535]

  $ ../../../jasmin-checksafety --config sum.json scan.jazz 2>&1 | grep -e Violation -e "mem_p:"
  *** No Safety Violation
    mem_p: [0; 64]
