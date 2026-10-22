On ARMv8-A a protect is an ORR followed by a CSDB. A run of protects that
do not read each other's results needs one CSDB, after the last ORR: run3
and ptrs print one. A protect that reads the result of the previous one
(chain), or any instruction between two protects (split), keeps both.

  $ for f in run3 chain split ptrs; do
  >   ../../jasminc -arch armv8a $f.jazz -o $f.s || echo "$f: failed"
  >   echo "$f: $(grep -c -i -w orr $f.s) orr, $(grep -c -i -w csdb $f.s) csdb"
  > done
  run3: 3 orr, 1 csdb
  chain: 2 orr, 2 csdb
  split: 2 orr, 2 csdb
  ptrs: 2 orr, 1 csdb
