# Task B selection — Swift

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.swift`: 2, 12, 13, 14, 15, 16, 29, 30, 31, 32, 33, 41, 42, 43, 44, 45, 46, 47, 54, 55, 56, 91, 92, 93, 94, 95, 96, 97, 98, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 507, 514, 515, 516, 517, 518, 519, 520, 521, 522, 543, 544, 545, 569, 616, 617, 618, 619, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713

## Evidence and language semantics

faces.filter preserves UTF8 face order. number validates decimal words before range checks. Local x advances twice. applySequence composes existing move permutations,also used by APPLY; state/history/redo operations remain identical. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace.

The excerpt contains 1244 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
