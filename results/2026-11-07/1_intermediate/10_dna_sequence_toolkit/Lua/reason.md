# Task B selection — Lua

## Answer requirements shared across languages

1. Locate GC's current truncating percentage conversion and explain nearest-hundredth rounding with exact halves upward.
2. Identify the local change boundary that preserves GCWINDOW percentages and the stored/counting base data.

## Selected source locations

- `main.lua`: 109, 110, 111, 112, 115, 116, 805, 812, 814, 818, 819

## Evidence and language semantics

pct floors scaled percentage before fixed formats hundredths. The selected GC and GCWINDOW callers share it, so apply the new rounding only at GC's conversion; keep base fields and window percentages unchanged. For nonnegative GC count g and positive length n, the new integer hundredths value is floor((20000*g+n)/(2*n)); this is exact half-up rounding before the same two-digit rendering. Integer quotient/remainder rounding with 2*remainder>=n is an equivalent option.

## Minimization and alternatives

The current conversion body and the two callers establish both the arithmetic and the necessary change boundary. The existing formatter is included only to establish the hundredths unit and two-digit representation. Unchanged sequence storage, base-count helper internals, window loops and validation are excluded. Changing the shared helper directly was rejected because it would also change GCWINDOW; a local GC conversion is sufficient.

The excerpt contains 250 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
