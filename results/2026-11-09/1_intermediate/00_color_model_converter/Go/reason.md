# Task B selection — Go

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.go`: 546, 548, 549, 550

## Evidence and language semantics

The slice scan identifies the existing entry index. For index >= 0 only that element's color is assigned. Slice element field assignment neither appends nor shifts entries.

## Minimization and alternatives

The successful lookup excludes append; its branch is not needed. Output and subsequent LIST sorting are unrelated.

The excerpt contains 93 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
