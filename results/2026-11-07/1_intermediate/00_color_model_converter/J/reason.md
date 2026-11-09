# Task B selection — J

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.ijs`: 393, 394, 396, 397, 398

## Evidence and language semantics

i. returns the matching name index. Existing position is below the name-vector length; amend } replaces the color row at that index while leaving rnames unchanged.

## Minimization and alternatives

The new-name else branch is excluded by the premise. Name/color binding plus the indexed amend suffices; no parser or LIST is required.

The excerpt contains 62 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
