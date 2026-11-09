# Task B selection — TypeScript

## Answer requirements shared across languages

1. Locate how ^0.2.3 constructs its upper version bound from parsed numeric components.
2. Use actual lower/upper comparator operations and version order to explain inclusion of 0.2.3 and exclusion of 0.3.0.

## Selected source locations

- `main.ts`: 82, 83, 118, 121, 123, 126, 131, 132, 133, 134, 135, 136, 152, 153, 154, 155, 156, 157, 185, 191, 192, 193, 194

## Evidence and language semantics

Caret chooses upper(2): core.map retains major,increments minor and zeros patch. Comparator evaluation explicitly maps >= to order>=0 and < to order<0. Thus ^0.2.3 constructs the pair >=0.2.3 and <0.3.0. At 0.2.3 the lower comparator sees equality and passes,while the upper comparator sees less-than and passes. At 0.3.0 the upper comparator sees equality and fails.

## Minimization and alternatives

Keep numeric component construction,the caret index choice,the upper-bound transformation and actual comparator evaluation. The core-order/equality fragment is included because version comparison is custom; prerelease ordering,invalid-input handling,wildcard alternatives,registry resolution and output are outside this stable-version boundary question. A caret formula alone would omit the required comparator evidence.

The excerpt contains 516 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
