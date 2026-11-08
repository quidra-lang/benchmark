# Task B selection — Lua

## Answer requirements shared across languages

1. Locate how ^0.2.3 constructs its upper version bound from parsed numeric components.
2. Use actual lower/upper comparator operations and version order to explain inclusion of 0.2.3 and exclusion of 0.3.0.

## Selected source locations

- `main.lua`: 79, 80, 81, 82, 83, 84, 99, 128, 132, 139, 143, 144, 145, 146, 147, 148, 149, 150, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 218, 219, 220, 221, 222, 223

## Evidence and language semantics

Caret selects one-based at=2. upper copies the core,increments minor and zeros patch. The evaluator explicitly applies order>=0 for >= and order<0 for < and stops on a failed comparator. Thus ^0.2.3 constructs the pair >=0.2.3 and <0.3.0. At 0.2.3 the lower comparator sees equality and passes,while the upper comparator sees less-than and passes. At 0.3.0 the upper comparator sees equality and fails.

## Minimization and alternatives

Keep numeric component construction,the caret index choice,the upper-bound transformation and actual comparator evaluation. The core-order/equality fragment is included because version comparison is custom; prerelease ordering,invalid-input handling,wildcard alternatives,registry resolution and output are outside this stable-version boundary question. A caret formula alone would omit the required comparator evidence.

The excerpt contains 631 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
