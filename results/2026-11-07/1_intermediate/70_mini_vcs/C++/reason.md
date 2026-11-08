# Task B selection — C++

## Answer requirements shared across languages

1. Identify the ancestry predicate selecting Already up to date in MERGE.
2. Use the local exit or exclusive branch structure and uncommitted-check position to explain whether that path bypasses the check; distinguish literal return from equivalent branch exclusion.

## Selected source locations

- `main.cpp`: 659, 661, 662, 663, 667, 668

## Evidence and language semantics

ancestor(target,old), with old=head(), selects Already up to date. This implementation uses an if/else-if/else chain rather than a literal early return: checkUncommitted() is inside the final else, so the true first branch bypasses it.

## Minimization and alternatives

Only the ancestry predicate, result/exit or exclusive branch boundaries, and the later cleanliness call are needed. The full merge procedure, ancestry traversal implementation, fast-forward mutations and conflict processing are unnecessary: the question concerns which predicate is used and its local control-flow ordering, not how ancestry is computed.

The excerpt contains 99 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
