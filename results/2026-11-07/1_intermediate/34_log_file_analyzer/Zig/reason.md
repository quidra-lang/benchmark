# Task B selection — Zig

## Answer requirements shared across languages

1. Trace STATUS class and code counts and the selected-request total to percentage scaling and two-decimal percent text.
2. Account for an empty selected set before division.
3. Identify a STATUS-only half-up rounding change while retaining every other percentage query's current rule.

## Selected source locations

- `main.zig`: 199, 200, 201, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 547, 548, 549, 550, 555, 556, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589

## Evidence and language semantics

STATUS counts and n flow through percentage and decimal; @divTrunc computes scaled hundredths and the dynamic format pads two places. requiresRecords identifies STATUS and bypasses rows.len=0. For a nonzero total let N=count*10000, q=floor(N/total), and r=N%total; round q upward exactly when 2*r>=total. Format the resulting q as q/100, a dot, q%100 padded to two digits, and %. Route only the STATUS percentage calls through this rounding calculation (or give them an explicit rounding option), retaining the shared truncating path for other queries. Keep the existing empty-selection output.

## Minimization and alternatives

The excerpt starts at the STATUS count/selected-total boundary; record parsing, filtering implementation and unrelated query calculations are unnecessary. Both STATUS percentage call sites are needed; changing only one misses category or exact-code rows. The shared arithmetic/formatting implementation and zero-selection guard are needed, but all its other callers can be omitted because the proposed change is explicitly routed only from STATUS. No proposed modification is implemented.

The excerpt contains 867 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
