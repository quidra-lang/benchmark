# Task B selection — R

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.R`: 302, 303, 304, 306, 307

## Evidence and language semantics

The name-indexed colors list is replaced with the parsed color. The separate order vector is extended only if the name is absent, so replacement preserves its existing position.

## Minimization and alternatives

The conditional order append is necessary evidence beyond list assignment. Printing and unregistration do not support the local answer.

The excerpt contains 83 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
