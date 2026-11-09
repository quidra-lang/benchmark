# Task B selection — Lua

## Answer requirements shared across languages

1. Locate the date-level month test and both day-of-month/day-of-week evaluation paths.
2. Explain month-failure early exit (or the existing equivalent short-circuit), why fire decisions stay false, and why no required state update or validation is skipped.

## Selected source locations

- `main.lua`: 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391

## Evidence and language semantics

scheduled currently obtains matchDay eagerly. Return false when fields[4].set[date.month] is not true before that call. The matchDay body only assigns local booleans and local intermediates, returning a condition without state changes or validation errors. A failing month already makes the final conjunction false regardless of the day booleans. For eager implementations, place the exit in the scheduling predicate, leaving the separate diagnostic day-status operation available to MATCH and other reporting. The change returns false for a date rather than advancing a loop manually, so caller iteration and its updates remain intact.

## Minimization and alternatives

For implementations that already short-circuit, the predicate alone proves the requested behavior and no day-helper body is needed. For eager implementations, the necessary helper body is included to show only local calculation is skipped, together with its caller and final month conjunction. Parsing and command validation remain outside this local predicate; no speculative bug investigation or unrelated query code is included. No proposed modification is implemented.

The excerpt contains 531 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
