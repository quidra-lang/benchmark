# Task B selection — C

## Answer requirements shared across languages

1. Identify the daily Sunday-or-holiday selection predicate.
2. Determine the immediate regular, overtime, and double-time minutes for a matching day, without expanding weekly computation.

## Selected source locations

- `main.c`: 245, 254, 255, 363, 364, 365, 366, 406, 412

## Evidence and language semantics

The predicate is day % 7 == 0 OR holidays[day]. Daily is zero-initialized; only values[2] becomes worked, so regular and overtime remain zero. The daily caller and hours_parts mapping establish index 0=regular, 1=overtime, 2=double.

## Minimization and alternatives

Retain only the predicate and immediate assigned values. Positional results additionally require the smallest available source mapping to category names; named records or bindings need no such caller expansion. Worked-time calculation, normal-day formulas and weekly adjustments are outside the requested immediate branch. Zero-initialization is retained where zeros are implicit.

The excerpt contains 184 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
