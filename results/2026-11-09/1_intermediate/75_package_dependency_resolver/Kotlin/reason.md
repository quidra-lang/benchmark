# Task B selection — Kotlin

## Answer requirements shared across languages

1. Locate how ^0.2.3 constructs its upper version bound from parsed numeric components.
2. Use actual lower/upper comparator operations and version order to explain inclusion of 0.2.3 and exclusion of 0.3.0.

## Selected source locations

- `main.kt`: 12, 13, 14, 15, 16, 58, 59, 62, 63, 72, 73, 74, 75, 105, 107, 109, 113, 116, 118, 120, 121, 122, 123, 124, 143, 144, 145

## Evidence and language semantics

The caret branch chooses upper(2); this copies the core,increments the second component and clears patch. accepts tests d>=0 for >= and d<0 for <,combined with all. Thus ^0.2.3 constructs the pair >=0.2.3 and <0.3.0. At 0.2.3 the lower comparator sees equality and passes,while the upper comparator sees less-than and passes. At 0.3.0 the upper comparator sees equality and fails.

## Minimization and alternatives

Keep numeric component construction,the caret index choice,the upper-bound transformation and actual comparator evaluation. The core-order/equality fragment is included because version comparison is custom; prerelease ordering,invalid-input handling,wildcard alternatives,registry resolution and output are outside this stable-version boundary question. A caret formula alone would omit the required comparator evidence.

The excerpt contains 534 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
