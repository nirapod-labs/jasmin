A loop stops only when its points-to sets are included in those of the
previous iteration. In lost.jazz the second iteration replaces p by a value
with no region and keeps every numerical dimension, so the test must still
see the third read, through p without a region. Without disjunctions on
if, the two branches are joined and nothing else tells the iterations
apart.

  $ ../../../jasmin-checksafety --config=nodisj.json lost.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "lost.jazz", line 14 (4-21): is_valid p u8
  Program is not safe!
  $ ../../../jasmin-checksafety lost.jazz 2>&1 | grep -e Violation -e line -e safe
  *** Possible Safety Violation(s):
    "lost.jazz", line 14 (4-21): is_valid p u8
  Program is not safe!

A pointer that keeps its region in every iteration stays safe.

  $ ../../../jasmin-checksafety --config=nodisj.json kept.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation
  $ ../../../jasmin-checksafety kept.jazz 2>&1 | grep -e Violation -e line -e safe
  *** No Safety Violation
