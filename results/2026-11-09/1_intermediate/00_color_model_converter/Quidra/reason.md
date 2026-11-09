# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.qui`: 33, 34, 35, 36, 37, 426, 427, 430, 431, 432

## Evidence and language semantics

index_of scans registered_names and returns the matching position. For a registered name, the nonnegative branch writes parsed[1] into the corresponding color element and changes no name position.

## Minimization and alternatives

index_of is custom and its name alone does not prove which position is chosen. The missing-name append path and output are outside the replacement premise.

The excerpt contains 123 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
