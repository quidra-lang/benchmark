# Task B selection — Ruby

## Answer requirements shared across languages

1. Identify the daily Sunday-or-holiday selection predicate.
2. Determine the immediate regular, overtime, and double-time minutes for a matching day, without expanding weekly computation.

## Selected source locations

- `main.rb`: 156, 241, 242, 274, 278

## Evidence and language semantics

The predicate is (day % 7).zero? OR @holidays.key?(day). Destructuring removes the initial worked element, then hours_parts labels the remaining values reg,ot,dbl: the special branch supplies 0,0,worked.

## Minimization and alternatives

Retain only the predicate and immediate assigned values. Positional results additionally require the smallest available source mapping to category names; named records or bindings need no such caller expansion. Worked-time calculation, normal-day formulas and weekly adjustments are outside the requested immediate branch. Zero-initialization is retained where zeros are implicit.

The excerpt contains 149 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
