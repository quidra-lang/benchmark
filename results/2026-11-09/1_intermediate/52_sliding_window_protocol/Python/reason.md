# Task B selection — Python

## Answer requirements shared across languages

1. Classify DELAYDATA as a list of colon-separated transmission-number/extra-tick integer pairs and identify both bounds.
2. Trace2:3 then2:4 through duplicate-number validation, identify the winning error, and prove no partial configuration enters simulation.

## Selected source locations

- `main.py`: 13, 14, 15, 16, 43, 44, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 90, 91, 92, 106, 107, 108, 109, 110, 111, 112, 113, 196, 197, 198, 199, 742, 743, 744, 745, 746, 747, 748, 749

## Evidence and language semantics

DELAYDATA is a list/delay key; delay_pair separately int-converts both colon fields. Both ranges pass, but distinct of the transmission-number projection2,2 is false. check_settings raises bad value for DELAYDATA before Config and the caller exits before Simulation. Both transmission numbers2 and extras3/4 satisfy their independent ranges1..9999 and1..50. The duplicate is on transmission number2, not on extra ticks, so the result is error: bad value for DELAYDATA. It is a bad list value rather than duplicate key because there is one DELAYDATA setting line. Validation stops or throws before the simulation call; temporary/local parsing state, even when partly populated, cannot become an active run. Standard split, integer parsing, set insertion/uniqueness and exception/return semantics suffice. Alternative delay-application/send code and simulation internals are unnecessary because this validation error prevents reaching them.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 544 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
