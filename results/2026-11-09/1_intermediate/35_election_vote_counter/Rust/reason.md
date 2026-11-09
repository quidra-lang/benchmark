# Task B selection — Rust

## Answer requirements shared across languages

1. Identify the local active-candidate field representing one SPOILERS exclusion scenario.
2. Determine whether retaining that field survives later exclusions and identify any needed independent copy using its construction and language value/reference semantics.

## Selected source locations

- `main.rs`: 6, 541, 743

## Evidence and language semantics

Field is u8, passed by value into tally after bitwise exclusion; Copy semantics give an independent scalar. The conclusion concerns candidate membership, not a deep copy of the election or ballot data. To retain the scenario, store its owning field value; current fresh-container or scalar/value constructions already provide the necessary independence, except a nonowning reference to a temporary must become an owning value.

## Minimization and alternatives

Only the scenario field construction and the declaration/storage needed to establish its ownership are selected. Vote counting, winner output, other election commands and complete Tally implementations are unrelated. Fresh-container library semantics, scalar copying, or language value semantics settle this question without tracing tally algorithms.

The excerpt contains 76 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
