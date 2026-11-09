# Task B selection — J

## Answer requirements shared across languages

1. Identify the default assigned by the signal-value initializer before events are processed.
2. Distinguish unknown X from a numeric or Boolean zero using the literal or its explicit encoding.

## Selected source locations

- `main.ijs`: 29, 281

## Evidence and language semantics

The initializer reshapes scalar 2 to the signal-vector shape. The selected '01X' index lookup explicitly maps character 0 to index 0 and X to index 2, so the initial 2 is the unknown representation, not numeric zero. No event or gate behavior is needed.

## Minimization and alternatives

The initializer is required to establish the actual default. The gate truth tables, event loop, input-value validator and status output are unnecessary for this narrowly scoped initializer question. Selecting a later output or validator without this assignment would not establish the initial value. The additional encoding line is necessary because the numeric literal 2 alone does not establish its X meaning; the compact index-to-character mapping is smaller than selecting all value-parsing branches.

The excerpt contains 20 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
