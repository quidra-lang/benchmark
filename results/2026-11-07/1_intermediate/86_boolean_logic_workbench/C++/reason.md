# Task B selection — C++

## Answer requirements shared across languages

1. Identify the TABLE header expression for a formula with an empty variable list.
2. Explain why it produces exactly | F, with no leading space and with the separator and result-column label retained.

## Selected source locations

- `main.cpp`: 641, 642

## Evidence and language semantics

The selected header construction is sufficient for the empty-variable case. Joining a sequence of variable labels followed by | and F inserts spaces only between surviving items; an empty-variable conditional contributes the empty string; a loop/map over an empty variable sequence contributes no prefix. Thus the header is exactly | F. Standard join, interpolation, conditional and empty-iteration semantics supply this result without inspecting formula parsing or truth evaluation. 

## Minimization and alternatives

The answer concerns only the header. Variable discovery, truth-table rows, formula evaluation and command parsing do not affect its empty-list representation and are omitted. For separate prefix loops or a mutable header accumulator, the prefix guard/loop and its final use must remain; taking only the literal | F could conceal an added leading space. A complete inline expression is smaller than tracing its surrounding dispatcher. Removing any selected construction line would hide either the conditional/empty-iteration rule or the actual header emission.

The excerpt contains 46 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
