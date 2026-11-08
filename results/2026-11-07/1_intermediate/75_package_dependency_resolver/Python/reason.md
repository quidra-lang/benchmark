# Task B selection — Python

## Answer requirements shared across languages

1. Locate how ^0.2.3 constructs its upper version bound from parsed numeric components.
2. Use actual lower/upper comparator operations and version order to explain inclusion of 0.2.3 and exclusion of 0.3.0.

## Selected source locations

- `main.py`: 21, 22, 32, 33, 34, 35, 36, 39, 40, 42, 43, 44, 45, 46, 75, 76, 77, 89, 90, 93, 94, 96, 116, 117, 118, 119, 120, 121, 122, 123, 124, 136

## Evidence and language semantics

The fallback caret case chooses position=2 for major=0,minor=2. upper_bound builds (0,3,0). Dataclass equality,total_ordering and tuple sort keys establish version order; COMPARISONS maps >= to operator.ge and < to operator.lt,combined by all. Thus ^0.2.3 constructs the pair >=0.2.3 and <0.3.0. At 0.2.3 the lower comparator sees equality and passes,while the upper comparator sees less-than and passes. At 0.3.0 the upper comparator sees equality and fails.

## Minimization and alternatives

Keep numeric component construction,the caret index choice,the upper-bound transformation and actual comparator evaluation. The core-order/equality fragment is included because version comparison is custom; prerelease ordering,invalid-input handling,wildcard alternatives,registry resolution and output are outside this stable-version boundary question. A caret formula alone would omit the required comparator evidence.

The excerpt contains 473 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
