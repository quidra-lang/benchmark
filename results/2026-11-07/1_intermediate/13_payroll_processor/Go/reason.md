# Task B selection — Go

## Answer requirements shared across languages

1. Identify the daily Sunday-or-holiday selection predicate.
2. Determine the immediate regular, overtime, and double-time minutes for a matching day, without expanding weekly computation.

## Selected source locations

- `main.go`: 274, 275, 295, 296, 417, 418, 473, 482

## Evidence and language semantics

The predicate is day%7 == 0 OR p.holidays[day]. Go zero-initializes Hours; only values[2] is set to worked. The daily caller and output mapping identify values[0:3] as reg, ot, dbl.

## Minimization and alternatives

Retain only the predicate and immediate assigned values. Positional results additionally require the smallest available source mapping to category names; named records or bindings need no such caller expansion. Worked-time calculation, normal-day formulas and weekly adjustments are outside the requested immediate branch. Zero-initialization is retained where zeros are implicit.

The excerpt contains 174 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
