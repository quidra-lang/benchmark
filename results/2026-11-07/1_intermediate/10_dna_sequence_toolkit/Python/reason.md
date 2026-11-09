# Task B selection — Python

## Answer requirements shared across languages

1. Locate GC's current truncating percentage conversion and explain nearest-hundredth rounding with exact halves upward.
2. Identify the local change boundary that preserves GCWINDOW percentages and the stored/counting base data.

## Selected source locations

- `main.py`: 70, 71, 72, 75, 76, 536, 537, 538, 543

## Evidence and language semantics

pct truncates with integer // before fixed renders hundredths. GC and GCWINDOW share pct. Replace only GC's numeric conversion with a rounded variant, leaving sequence.count output and the window caller unchanged. For nonnegative GC count g and positive length n, the new integer hundredths value is floor((20000*g+n)/(2*n)); this is exact half-up rounding before the same two-digit rendering. Integer quotient/remainder rounding with 2*remainder>=n is an equivalent option.

## Minimization and alternatives

The current conversion body and the two callers establish both the arithmetic and the necessary change boundary. The existing formatter is included only to establish the hundredths unit and two-digit representation. Unchanged sequence storage, base-count helper internals, window loops and validation are excluded. Changing the shared helper directly was rejected because it would also change GCWINDOW; a local GC conversion is sufficient.

The excerpt contains 220 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
