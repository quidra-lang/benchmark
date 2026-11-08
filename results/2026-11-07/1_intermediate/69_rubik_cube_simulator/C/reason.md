# Task B selection — C

## Answer requirements shared across languages

1. Follow valid SCRAMBLE count/seed parsing and ranges to ordered face candidates and the previous exclusions.
2. Explain replacing exclusions by previous-axis exclusion while preserving URFDLB candidate order,exactly two LCG draws per move,amount mapping and seed handling.
3. Trace generated moves through shared application and notation output plus separately observable STATE,showing non-scramble move behavior is unchanged.

## Selected source locations

- `main.c`: 47, 127, 128, 129, 131, 132, 133, 166, 167, 177, 178, 179, 180, 181, 182, 184, 185, 186, 187, 209, 211, 212, 213, 215, 216, 217, 218, 219, 220, 221, 222, 661, 662, 663, 664, 665, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 717, 720, 721, 722, 723, 724, 725, 737, 756, 842, 843, 844, 845, 846, 847, 848, 849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864

## Evidence and language semantics

faces is URFDLB; axis uses R/L=0,U/D=1,F/B=2. The generator builds usable in that order,excludes the same face and only the third same-axis move,then makes exactly two LCG advances. apply_current uses the same permutation loop for SCRAMBLE and APPLY and updates history/redo. Replace the existing two exclusions with a single previous-move axis inequality whenever a previous move exists. The first move keeps all six faces; thereafter remove both faces on the previous axis. Keep the ordered candidate construction and modulo selection,not rejection sampling,so exactly two draws remain. Keep count 1..50,seed 1..2147483646,the LCG constants and amount mapping. The SCRAMBLE command prints generated notation and changes the cube; STATE is the separate command that prints the resulting stickers. Do not change the shared move application or parsing of non-scramble moves.

## Minimization and alternatives

The excerpt contains validated count/seed input,candidate axis/order,current exclusions,both draws,amount mapping,existing move application and observable notation/state outputs. Permutation-table construction,search,simplification,undo and full move grammar are unchanged and not required to locate this generator-only change. The whole simulator would be much larger; the candidate predicate alone would omit the required deterministic draw and application trace. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1601 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
