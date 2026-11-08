# Task B selection — Python

## Answer requirements shared across languages

1. Identify the daily Sunday-or-holiday selection predicate.
2. Determine the immediate regular, overtime, and double-time minutes for a matching day, without expanding weekly computation.

## Selected source locations

- `main.py`: 168, 169

## Evidence and language semantics

The predicate is day % 7 == 0 OR day in self.holidays. Tuple assignment immediately sets regular=0, overtime=0, double=worked.

## Minimization and alternatives

Retain only the predicate and immediate assigned values. Positional results additionally require the smallest available source mapping to category names; named records or bindings need no such caller expansion. Worked-time calculation, normal-day formulas and weekly adjustments are outside the requested immediate branch. Zero-initialization is retained where zeros are implicit.

The excerpt contains 46 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
