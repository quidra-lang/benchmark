# Task B selection — PHP

## Answer requirements shared across languages

1. Classify DELAYDATA as a list of colon-separated transmission-number/extra-tick integer pairs and identify both bounds.
2. Trace2:3 then2:4 through duplicate-number validation, identify the winning error, and prove no partial configuration enters simulation.

## Selected source locations

- `main.php`: 17, 98, 99, 100, 101, 102, 103, 104, 105, 106, 210, 211, 212, 213, 214, 215, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859

## Evidence and language semantics

DELAY_KEYS classifies the setting; explode and intval separate number2 from extras3/4. Bounds pass but isset(numbers[2]) returns false validation; checkSettings throws bad value for DELAYDATA before Config, and execute returns before creating Simulation. Both transmission numbers2 and extras3/4 satisfy their independent ranges1..9999 and1..50. The duplicate is on transmission number2, not on extra ticks, so the result is error: bad value for DELAYDATA. It is a bad list value rather than duplicate key because there is one DELAYDATA setting line. Validation stops or throws before the simulation call; temporary/local parsing state, even when partly populated, cannot become an active run. Standard split, integer parsing, set insertion/uniqueness and exception/return semantics suffice. Alternative delay-application/send code and simulation internals are unnecessary because this validation error prevents reaching them.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 445 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
