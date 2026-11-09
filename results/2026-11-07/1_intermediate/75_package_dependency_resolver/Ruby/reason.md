# Task B selection — Ruby

## Answer requirements shared across languages

1. Locate how ^0.2.3 constructs its upper version bound from parsed numeric components.
2. Use actual lower/upper comparator operations and version order to explain inclusion of 0.2.3 and exclusion of 0.3.0.

## Selected source locations

- `main.rb`: 19, 20, 21, 22, 62, 64, 66, 70, 75, 76, 77, 79, 80, 81, 82, 83, 99, 100, 101, 112, 113, 114, 115, 116, 117, 118

## Evidence and language semantics

Caret chooses one-based i=2; upper duplicates the core,increments minor and clears patch. Comparable supplies ordering from <=>; matching applies comparison>=0 and comparison.negative? under all?. Thus ^0.2.3 constructs the pair >=0.2.3 and <0.3.0. At 0.2.3 the lower comparator sees equality and passes,while the upper comparator sees less-than and passes. At 0.3.0 the upper comparator sees equality and fails.

## Minimization and alternatives

Keep numeric component construction,the caret index choice,the upper-bound transformation and actual comparator evaluation. The core-order/equality fragment is included because version comparison is custom; prerelease ordering,invalid-input handling,wildcard alternatives,registry resolution and output are outside this stable-version boundary question. A caret formula alone would omit the required comparator evidence.

The excerpt contains 457 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
