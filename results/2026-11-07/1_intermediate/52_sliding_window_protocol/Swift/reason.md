# Task B selection — Swift

## Answer requirements shared across languages

1. Classify DELAYDATA as a list of colon-separated transmission-number/extra-tick integer pairs and identify both bounds.
2. Trace2:3 then2:4 through duplicate-number validation, identify the winning error, and prove no partial configuration enters simulation.

## Selected source locations

- `main.swift`: 23, 24, 25, 79, 80, 81, 82, 83, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 141, 142, 143, 662, 663, 664, 665

## Evidence and language semantics

Key19 is a list setting. split/Int produces number and extra; Set.insert.inserted rejects second2 while both ranges pass. fail throws bad value for DELAYDATA; catch emits error and the simulation call is reached only after successful validation. Both transmission numbers2 and extras3/4 satisfy their independent ranges1..9999 and1..50. The duplicate is on transmission number2, not on extra ticks, so the result is error: bad value for DELAYDATA. It is a bad list value rather than duplicate key because there is one DELAYDATA setting line. Validation stops or throws before the simulation call; temporary/local parsing state, even when partly populated, cannot become an active run. Standard split, integer parsing, set insertion/uniqueness and exception/return semantics suffice. Alternative delay-application/send code and simulation internals are unnecessary because this validation error prevents reaching them.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 497 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
