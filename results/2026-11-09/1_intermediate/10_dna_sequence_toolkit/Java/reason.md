# Task B selection — Java

## Answer requirements shared across languages

1. Locate GC's current truncating percentage conversion and explain nearest-hundredth rounding with exact halves upward.
2. Identify the local change boundary that preserves GCWINDOW percentages and the stored/counting base data.

## Selected source locations

- `Main.java`: 59, 60, 61, 62, 460, 463, 466, 468

## Evidence and language semantics

pct truncates integer 10000*a/b and fixed formats hundredths with width two. It is used in both GC and GCWINDOW. Use a GC-only rounded variant at the GC call, preserving lineOut base counts and the original window conversion. For nonnegative GC count g and positive length n, the new integer hundredths value is floor((20000*g+n)/(2*n)); this is exact half-up rounding before the same two-digit rendering. Integer quotient/remainder rounding with 2*remainder>=n is an equivalent option.

## Minimization and alternatives

The current conversion body and the two callers establish both the arithmetic and the necessary change boundary. The existing formatter is included only to establish the hundredths unit and two-digit representation. Unchanged sequence storage, base-count helper internals, window loops and validation are excluded. Changing the shared helper directly was rejected because it would also change GCWINDOW; a local GC conversion is sufficient.

The excerpt contains 250 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
