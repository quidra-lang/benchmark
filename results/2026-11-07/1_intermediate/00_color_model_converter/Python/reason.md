# Task B selection — Python

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.py`: 258, 329, 330, 332, 333

## Evidence and language semantics

DEFINE is dispatched to define. Its parsed color replaces self.registered[name]. Python dict assignment to an existing key preserves insertion order.

## Minimization and alternatives

The handler mapping binds DEFINE to this method; unrelated handler entries share the complete mapping line. No color parsing or LIST internals are needed for dict replacement.

The excerpt contains 92 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
