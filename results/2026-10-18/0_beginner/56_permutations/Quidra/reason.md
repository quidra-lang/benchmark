# Task B selection: 56_permutations / Quidra

## Answer requirements

Trace the transition from the last A-prefixed permutation to the first B-prefixed permutation, explain relinquished choices and availability, and locate sequence-number assignment.

## Answer supported by the selected source

The last A-prefixed completion is ADCB, numbered 6. Returning unwinds prefixes ADCB, ADC, AD and A until the root call tries B. No explicit character reset is needed: each recursive call receives its own prefix value, and the caller's shorter prefix is unchanged when that call returns. prefix.contains excludes exactly the characters in that call's partial permutation. The B call chooses A, then C, then D, yielding BACD, numbered 7. The completion branch increments count before printing and returns it through the recursive assignments.

## Evidence and alternatives

The signature establishes value parameters. The completion guard, increment, print and return establish numbering and the base case. ABCD, index iteration, membership guard and recursive concatenation establish search order and availability. Both count returns and the initial call establish the count carried between subtrees. The original parallel used array was considered; prefix already contains the complete set of chosen characters, so that state and its mutations are unnecessary for this recursive algorithm. No permutation-generating library is used.

Selected complete main.qui source lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 4edefba77b30a2a7d55e2849f30e2d022fb1f6b2d12d7319f45293830459555a): Task A 138 tokens; Task B 137 tokens. Original values: Task A 134; Task B 133. Task B proposed modifications have not been implemented. Native validation of Task A is recorded separately in validation-results.json; lexical counts or excerpt review do not by themselves establish compilation or correctness.
