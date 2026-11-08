# Task B selection — Zig

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.zig`: 418, 419, 420, 421, 474, 482, 483, 484

## Evidence and language semantics

registeredIndex scans entries in order and yields the matching name index. DEFINE replaces only entries[index].color with the parsed value, preserving the same entry slot.

## Minimization and alternatives

registeredIndex is custom so include the matching return. Its null return and new-name branch are excluded by the existing-name premise; formatting is unnecessary.

The excerpt contains 183 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
