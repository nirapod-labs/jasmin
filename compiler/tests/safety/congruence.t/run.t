Passing congruences on for the written variables only gives the same
verdict here as passing all of them after every operation; not passing them
at all loses the fact that x == 4 cannot hold.

  $ ../../../jasmin-checksafety aligned.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "aligned.jazz", line 10 (16-25): is_init a[x]
  Program is not safe!

  $ ../../../jasmin-checksafety --config cr1.json aligned.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "aligned.jazz", line 10 (16-25): is_init a[x]
  Program is not safe!

  $ ../../../jasmin-checksafety --config cr0.json aligned.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "aligned.jazz", line 10 (16-25): is_init a[x]
    "aligned.jazz", line 10 (16-25): in_bound: a[x] (length 8 U8)
  Program is not safe!
