# Task B selection — C

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.c`: 22, 23, 24, 29, 652, 655

## Evidence and language semantics

DEFINE calls registry_set. Its scan stops at the existing name and assigns only entries[i].color; the same array slot, name and ordering are retained.

## Minimization and alternatives

The existing-name premise makes the new-entry branch unnecessary. The call alone cannot establish custom helper mutation; the scan and exact field assignment do. Formatting and LIST sorting answer a different operation.

The excerpt contains 124 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
