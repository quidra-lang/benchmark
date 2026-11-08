# Task B selection — Lua

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.lua`: 490, 491, 493, 494, 495, 496

## Evidence and language semantics

For an existing key the nil guard is false, so registry.order is not appended; only registry.colors[name] is replaced with the color copy.

## Minimization and alternatives

The order guard is required because order is stored separately. copy_color does not decide order, so its internals are unnecessary under the valid RGB assumption.

The excerpt contains 91 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
