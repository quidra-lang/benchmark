# Task B selection — Kotlin

## Answer requirements shared across languages

1. Locate SIMULATE validation and construction of the enabled transitions in original transition order.
2. Explain changing only RANDOM candidate selection to the order-preserving subset whose priorities equal the maximum among enabled transitions; leave PRIORITY selection unchanged.
3. Retain the generator recurrence, one advancement for each nondead firing even for one candidate, updated-state modulo selection and no advancement for an empty enabled set.
4. Trace the unchanged commit/history, marking, step/completion output and per-transition counts.

## Selected source locations

- `main.kt`: 155, 160, 161, 162, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663

## Evidence and language semantics

The simulation branch validates steps, seed in 1..2147483646 and mode before constructing counts and iterating. The selected enabled-list construction enumerates transition indices in declaration order and applies the existing enabledness predicate; no enabledness predicate changes are needed. In RANDOM, first compute the maximum priority over that nonempty list and filter the same list, in order, to equal-priority entries. Advance the existing state exactly once with x = 48271*x mod 2147483647, then select candidates[x mod size] (add one only for one-based host indexing). Keep the advance even when size is one. The dead check precedes this branch and must continue to return/break without a draw. The PRIORITY branch already exposes the maximum-priority comparison and keeps its original tie convention. Commit records the pre-firing marking and installs the successor; counts and step/completion/counts lines consume the selected transition exactly as before. The generator is exact in the supported integer range; standard stable filter/map/range iteration retains the candidate order. 

## Minimization and alternatives

The candidate construction and the priority comparison provide a smaller modification boundary than selecting transition/net parsing or all enabledness checks: the proposal keeps those checks unchanged and reuses their result. The commit body is included because history cannot be inferred from a custom function name. The validation and output/count lines are retained because the question explicitly preserves them. Unrelated graph, coverability, invariant and undo analysis is omitted. The RANDOM branch must not reuse a single highest-priority winner from PRIORITY, since that would remove equal-priority candidates; filtering the existing ordered enabled list is the smaller sufficient change. Task A is not modified.

The excerpt contains 663 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
