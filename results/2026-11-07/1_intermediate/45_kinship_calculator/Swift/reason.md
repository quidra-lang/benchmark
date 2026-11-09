# Task B selection — Swift

## Answer requirements shared across languages

1. Identify one ancestor-distance or visited working binding used by RELATION, citing its construction and one update.
2. Explain whether that working value aliases mutable registered parent data and whether changing it can change a registered parent list.

## Selected source locations

- `main.swift`: 161, 163, 171

## Evidence and language semantics

distances is a Dictionary value initialized with id:0 and then updated. Swift Dictionary value semantics preserve separate logical values even if storage is internally shared. The construction and update suffice to distinguish the distance container from source parent data; immutability of identifier/number values or value semantics prevents an indirect parent-list edit through these distance entries. This does not assert that no other cache aliases the distance value itself.

## Minimization and alternatives

The constructor plus one update gives a smaller sufficient proof than the complete breadth-first traversal, parent lookup implementations, or RELATION formatting. Queue management, pedigree traversal and registered-data editing commands are excluded because they add no ownership fact required by the question.

The excerpt contains 52 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
