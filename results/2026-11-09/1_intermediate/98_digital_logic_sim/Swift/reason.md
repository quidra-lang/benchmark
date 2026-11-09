# Task B selection — Swift

## Answer requirements shared across languages

1. Identify the default assigned by the signal-value initializer before events are processed.
2. Distinguish unknown X from a numeric or Boolean zero using the literal or its explicit encoding.

## Selected source locations

- `main.swift`: 392, 393, 394

## Evidence and language semantics

The selected initializer assigns or fills the signal-value storage with the quoted X literal. Its literal kind is directly determined by the language: a character or string, distinct from numeric zero, Boolean false, and the quoted zero character. The initializer itself provides the requested default without invoking event processing.

## Minimization and alternatives

The initializer is required to establish the actual default. The gate truth tables, event loop, input-value validator and status output are unnecessary for this narrowly scoped initializer question. Selecting a later output or validator without this assignment would not establish the initial value.

The excerpt contains 38 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
