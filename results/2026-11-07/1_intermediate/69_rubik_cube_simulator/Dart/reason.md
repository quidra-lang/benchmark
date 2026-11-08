# Task B selection — Dart

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.dart`: 8, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 86, 87, 88, 89, 90, 91, 92, 93, 195, 196, 197, 198, 199, 626, 627, 628, 629, 630, 656, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 711, 712, 713, 714, 715, 716, 727, 728, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880

## Evidence and language semantics

faces.split and where preserve URFDLB order. next captures local parsed seed; two calls choose face and amount. apply composes and applies existing permutations,and updates history/redo for both command cases. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace.

The excerpt contains 1187 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
