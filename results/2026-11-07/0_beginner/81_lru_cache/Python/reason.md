# Task B selection: 81_lru_cache / Python

## Answer requirements

Explain the cache-access operation from an accessed key and current cache order to its next order, status and hit/miss totals. Use the fourth access B and following D to cover refreshing a hit and inserting a miss with eviction. Identify whether updates mutate shared cache storage or create/rebind replacement values, which state the next access reads, and whether the original access sequence shares that mutable ordering storage.

## Answer and source evidence

After B,A,C the cache is C A B (most to least recent). Fourth access B is a hit: remove B then put it at front, giving B C A. Next access D is a miss with capacity3: evict tail A and insert D, giving D B C. Hit/miss counters advance only in their respective branch; the next access reads the updated cache. Cache storage is separate from the literal/list or string access sequence, which never shares its mutable ordering storage. The selected membership/removal, tail eviction, head insertion and status output define one complete access operation.



Selected `main.py` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
