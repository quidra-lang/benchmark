# Task B selection — Rust

## Answer requirements shared across languages

1. Identify the default assigned by the signal-value initializer before events are processed.
2. Distinguish unknown X from a numeric or Boolean zero using the literal or its explicit encoding.

## Selected source locations

- `main.rs`: 75, 696

## Evidence and language semantics

The signal-value field v is initialized by vec![2; n]. The selected character conversion indexes b"01X" by v, establishing that encoded value 2 means X and value 0 means character 0. Thus this byte-vector initializer does not default to false/zero.

## Minimization and alternatives

The initializer is required to establish the actual default. The gate truth tables, event loop, input-value validator and status output are unnecessary for this narrowly scoped initializer question. Selecting a later output or validator without this assignment would not establish the initial value. The additional encoding line is necessary because the numeric literal 2 alone does not establish its X meaning; the compact index-to-character mapping is smaller than selecting all value-parsing branches.

The excerpt contains 34 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
