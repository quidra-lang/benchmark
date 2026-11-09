# Task B selection — Lua

## Answer requirements shared across languages

1. Locate the PROC burst-kind character comparison and its independent length conversion.
2. Explain local ASCII case normalization of that character only, preserving IDs, algorithm names, lengths, and uppercase output.

## Selected source locations

- `main.lua`: 69, 485, 486, 487

## Evidence and language semantics

sub(1,1) isolates the kind; sub(2) supplies the numeric length. Description uses uppercase parity. Apply the language's uppercase operation only to the extracted one-character kind (or its ASCII byte), before comparing with the unchanged C/I expectation. Do not uppercase a whole command, process ID, algorithm name, numeric tail, or stored description. Known indexing/slicing and standard ASCII case-conversion semantics suffice; no scheduler internals are needed.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 117 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
