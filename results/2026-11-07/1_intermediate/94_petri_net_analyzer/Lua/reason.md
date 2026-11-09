# Task B selection — Lua

## Answer requirements shared across languages

1. Locate SIMULATE validation and construction of the enabled transitions in original transition order.
2. Explain changing only RANDOM candidate selection to the order-preserving subset whose priorities equal the maximum among enabled transitions; leave PRIORITY selection unchanged.
3. Retain the generator recurrence, one advancement for each nondead firing even for one candidate, updated-state modulo selection and no advancement for an empty enabled set.
4. Trace the unchanged commit/history, marking, step/completion output and per-transition counts.

## Selected source locations

- `main.lua`: 245, 246, 247, 248, 249, 250, 251, 252, 261, 262, 263, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954

## Evidence and language semantics

The simulation branch validates steps, seed in 1..2147483646 and mode before constructing counts and iterating. The selected enabled-list construction enumerates transition indices in declaration order and applies the existing enabledness predicate; no enabledness predicate changes are needed. In RANDOM, first compute the maximum priority over that nonempty list and filter the same list, in order, to equal-priority entries. Advance the existing state exactly once with x = 48271*x mod 2147483647, then select candidates[x mod size] (add one only for one-based host indexing). Keep the advance even when size is one. The dead check precedes this branch and must continue to return/break without a draw. The PRIORITY branch already exposes the maximum-priority comparison and keeps its original tie convention. Commit records the pre-firing marking and installs the successor; counts and step/completion/counts lines consume the selected transition exactly as before. The generator is exact in the supported integer range; standard stable filter/map/range iteration retains the candidate order. 

## Minimization and alternatives

The candidate construction and the priority comparison provide a smaller modification boundary than selecting transition/net parsing or all enabledness checks: the proposal keeps those checks unchanged and reuses their result. The commit body is included because history cannot be inferred from a custom function name. The validation and output/count lines are retained because the question explicitly preserves them. Unrelated graph, coverability, invariant and undo analysis is omitted. The RANDOM branch must not reuse a single highest-priority winner from PRIORITY, since that would remove equal-priority candidates; filtering the existing ordered enabled list is the smaller sufficient change. Task A is not modified.

The excerpt contains 722 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
