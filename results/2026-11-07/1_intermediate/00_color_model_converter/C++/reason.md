# Task B selection — C++

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.cpp`: 41, 42, 43, 44, 45, 660, 663

## Evidence and language semantics

DEFINE invokes registry_set; a reference to the matching entry receives color and immediately returns. Reference field assignment preserves the vector element and its position.

## Minimization and alternatives

Retain return to show the append path is not reached. The push_back branch and LIST sorting are unnecessary for replacement.

The excerpt contains 115 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
