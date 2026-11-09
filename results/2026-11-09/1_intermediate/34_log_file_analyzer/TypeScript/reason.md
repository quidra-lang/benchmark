# Task B selection — TypeScript

## Answer requirements shared across languages

1. Trace STATUS class and code counts and the selected-request total to percentage scaling and two-decimal percent text.
2. Account for an empty selected set before division.
3. Identify a STATUS-only half-up rounding change while retaining every other percentage query's current rule.

## Selected source locations

- `main.ts`: 18, 19, 158, 159, 160, 161, 162, 163, 164, 288, 289, 290, 291, 320, 321, 322, 323, 324, 325, 326

## Evidence and language semantics

STATUS supplies category/code counts and records.length; percent plus decimal scale by 10000, Math.floor truncates, and padStart supplies the two-place fraction. REQUIRE_RECORDS prevents zero division. For a nonzero total let N=count*10000, q=floor(N/total), and r=N%total; round q upward exactly when 2*r>=total. Format the resulting q as q/100, a dot, q%100 padded to two digits, and %. Route only the STATUS percentage calls through this rounding calculation (or give them an explicit rounding option), retaining the shared truncating path for other queries. Keep the existing empty-selection output.

## Minimization and alternatives

The excerpt starts at the STATUS count/selected-total boundary; record parsing, filtering implementation and unrelated query calculations are unnecessary. Both STATUS percentage call sites are needed; changing only one misses category or exact-code rows. The shared arithmetic/formatting implementation and zero-selection guard are needed, but all its other callers can be omitted because the proposed change is explicitly routed only from STATUS. No proposed modification is implemented.

The excerpt contains 456 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
