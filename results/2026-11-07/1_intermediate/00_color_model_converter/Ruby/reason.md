# Task B selection — Ruby

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.rb`: 46, 394, 395, 397, 398

## Evidence and language semantics

The receiver is a Ruby Hash. Assigning a new value to an existing key preserves its insertion order; the color_argument result replaces that name's RGB.

## Minimization and alternatives

Hash initialization supplies known ordered Hash semantics. Validation, conversion internals and sorted LIST formatting do not change replacement.

The excerpt contains 60 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
