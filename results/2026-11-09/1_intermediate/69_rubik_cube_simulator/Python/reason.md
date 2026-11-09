# Task B selection — Python

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.py`: 8, 21, 22, 27, 28, 33, 34, 40, 49, 92, 93, 94, 95, 102, 117, 142, 143, 144, 145, 146, 147, 148, 182, 183, 205, 206, 207, 208, 427, 428, 429, 430, 431, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 590, 591, 592, 593, 609, 610, 715, 716, 717, 718, 719, 720, 721, 722, 723, 771, 775, 776, 777, 778, 779, 780, 781, 782, 792

## Evidence and language semantics

AXIS reads the first turn component,with opposite pairs explicitly shown. minstd yields the LCG sequence; scramble consumes two next calls per move. list/remove/filter preserve FACES order. WORD_COMMANDS validates two NUMBER words before int conversion and method dispatch. record is shared with do_apply. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace.

The excerpt contains 1106 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
