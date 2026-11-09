# Task B selection — C++

## Answer requirements shared across languages

1. Locate the date-level month test and both day-of-month/day-of-week evaluation paths.
2. Explain month-failure early exit (or the existing equivalent short-circuit), why fire decisions stay false, and why no required state update or validation is skipped.

## Selected source locations

- `main.cpp`: 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228

## Evidence and language semantics

scheduled currently calls days before its month &&. Move the month rejection before that call (or put days behind the right operand). days only computes local dom/dow and nearest-date results; it performs no state write or validation. A failing month already makes the final conjunction false regardless of the day booleans. For eager implementations, place the exit in the scheduling predicate, leaving the separate diagnostic day-status operation available to MATCH and other reporting. The change returns false for a date rather than advancing a loop manually, so caller iteration and its updates remain intact.

## Minimization and alternatives

For implementations that already short-circuit, the predicate alone proves the requested behavior and no day-helper body is needed. For eager implementations, the necessary helper body is included to show only local calculation is skipped, together with its caller and final month conjunction. Parsing and command validation remain outside this local predicate; no speculative bug investigation or unrelated query code is included. No proposed modification is implemented.

The excerpt contains 645 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
