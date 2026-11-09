# Task B selection — PHP

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.php`: 444, 445, 447, 448, 449, 450

## Evidence and language semantics

The order array is appended only for a missing color key. Replacing the existing registry colors entry leaves registry order untouched; PHP array value assignment replaces RGB.

## Minimization and alternatives

The separate order guard cannot be inferred from a colors update alone. Input validation, copy-on-write implementation details and result text are excluded.

The excerpt contains 103 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
