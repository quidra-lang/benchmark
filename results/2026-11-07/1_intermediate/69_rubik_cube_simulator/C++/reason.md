# Task B selection — C++

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.cpp`: 14, 23, 24, 25, 37, 38, 39, 40, 41, 45, 46, 47, 48, 49, 93, 94, 95, 96, 97, 162, 163, 164, 165, 166, 167, 168, 443, 444, 445, 446, 458, 459, 460, 461, 462, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 537, 548, 549, 552, 553, 571, 572, 573, 576, 577, 591, 657, 658, 659, 660, 661, 662, 663

## Evidence and language semantics

scramble preserves faces order and captures the passed seed by value in a local LCG closure. Its two calls choose face then amount. apply shares the existing effect/permutation path with APPLY; moves_text adds the space prefixes printed after scramble. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace.

The excerpt contains 1555 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
