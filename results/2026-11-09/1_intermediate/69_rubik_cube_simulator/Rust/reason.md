# Task B selection — Rust

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.rs`: 4, 16, 17, 18, 19, 20, 45, 46, 47, 48, 49, 50, 51, 62, 63, 64, 65, 66, 67, 68, 69, 70, 98, 99, 100, 101, 102, 103, 104, 363, 364, 365, 366, 367, 368, 369, 370, 371, 541, 542, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 580, 581, 582, 583, 584, 585, 586, 587, 617, 690, 691, 692, 693, 694, 695, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825

## Evidence and language semantics

FACES.bytes.filter retains order; number validates decimal input before count/seed ranges. Local x advances twice and yields amount 1,3,2. SCRAMBLE and APPLY use the same apply_sequence effect/permutation method and state/history/redo operations. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace.

The excerpt contains 1455 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
