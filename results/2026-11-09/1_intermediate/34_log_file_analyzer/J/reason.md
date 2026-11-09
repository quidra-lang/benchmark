# Task B selection — J

## Answer requirements shared across languages

1. Trace STATUS class and code counts and the selected-request total to percentage scaling and two-decimal percent text.
2. Account for an empty selected set before division.
3. Identify a STATUS-only half-up rounding change while retaining every other percentage query's current rule.

## Selected source locations

- `main.ijs`: 7, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 800, 801, 802, 803, 804

## Evidence and language semantics

STATUS uses count,n pairs. percent multiplies by 100x, decimal scales by 10x^2, and floor_ratio floors exact extended-integer division; padded makes two digits. NEED_RECORDS bypasses this for empty idx. For a nonzero total let N=count*10000, q=floor(N/total), and r=N%total; round q upward exactly when 2*r>=total. Format the resulting q as q/100, a dot, q%100 padded to two digits, and %. Route only the STATUS percentage calls through this rounding calculation (or give them an explicit rounding option), retaining the shared truncating path for other queries. Keep the existing empty-selection output.

## Minimization and alternatives

The excerpt starts at the STATUS count/selected-total boundary; record parsing, filtering implementation and unrelated query calculations are unnecessary. Both STATUS percentage call sites are needed; changing only one misses category or exact-code rows. The shared arithmetic/formatting implementation and zero-selection guard are needed, but all its other callers can be omitted because the proposed change is explicitly routed only from STATUS. No proposed modification is implemented.

The excerpt contains 454 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
