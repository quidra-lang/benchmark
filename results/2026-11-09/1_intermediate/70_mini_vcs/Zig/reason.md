# Task B selection — Zig

## Answer requirements shared across languages

1. Identify the ancestry predicate selecting Already up to date in MERGE.
2. Use the local exit or exclusive branch structure and uncommitted-check position to explain whether that path bypasses the check; distinguish literal return from equivalent branch exclusion.

## Selected source locations

- `main.zig`: 378, 563, 564, 565, 566, 574

## Evidence and language semantics

h=self.head(); ancestor(gpa,c,h) prints Already up to date and returns before requireClean().

## Minimization and alternatives

Only the ancestry predicate, result/exit or exclusive branch boundaries, and the later cleanliness call are needed. The full merge procedure, ancestry traversal implementation, fast-forward mutations and conflict processing are unnecessary: the question concerns which predicate is used and its local control-flow ordering, not how ancestry is computed.

The excerpt contains 90 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
