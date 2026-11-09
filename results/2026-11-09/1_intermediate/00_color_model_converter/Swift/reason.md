# Task B selection — Swift

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.swift`: 247, 250, 251, 252

## Evidence and language semantics

The new Entry uses the same name and parsed RGB. firstIndex finds the existing array position and indexed assignment replaces exactly that element; Array subscript replacement preserves ordering.

## Minimization and alternatives

The existing-name premise excludes append. No need for validation, result text or sorted LIST output.

The excerpt contains 103 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
