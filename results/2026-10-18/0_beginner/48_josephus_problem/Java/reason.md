# Task B selection: 48_josephus_problem / Java

## Common answer requirements

Trace the first three removals for the supplied case n=7, k=3, including the next starting person and wraparound.

## Source evidence

The collection operation removes one element at the computed position and shifts later elements down. The initial circle is [1,2,3,4,5,6,7], with index 0. Advancing by k−1 gives (0+2) mod 7 = 2, removing 3; index 2 then points at 4. The next index is (2+2) mod 6 = 4, removing 6; index 4 then points at 7. The third count visits 7, 1, 2, and (4+2) mod 5 = 1 removes 2. The retained loop repeats these updates without resetting index. Where a collection is one-based, lookup or removal translates the zero-based index.

## Minimization

The case values come from the question; a separate literal declaration is unnecessary when the selected algorithm identifies their roles. The removal operation itself identifies the removed person without a duplicate read just for printing or storing the removal.

Selected complete lines of `Main.java`: 7–8, 10–15. The prior excerpt measured 215 tokens; this excerpt measures 168 with `metric/tokenizer.py`.

## Current token measurement

Task A: **378 tokens**. Task B: **165 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
