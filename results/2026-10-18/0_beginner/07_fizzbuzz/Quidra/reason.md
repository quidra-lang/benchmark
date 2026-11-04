# Task B selection: 07_fizzbuzz / Quidra

## Common answer requirements

1. Explain why 15 and 30 select the combined FizzBuzz branch.
2. Show that divisibility by 15 is tested before the alternatives and that this branch emits one complete line.

## Implementation decision

Use println for each complete branch output and remove the separate newline call after the conditional. The divisibility algorithm and exclusive branch order remain unchanged. Task A grows by one lexical token while the direct line-output operation makes newline behavior explicit at the selected branch and shortens its understanding evidence.

## Evidence and answer

The first predicate accepts both question-supplied values, and println writes FizzBuzz followed by one newline. The elif headers show that the 3 and 5 decisions are mutually exclusive alternatives to that first branch. Their shorter-word bodies and numeric fallback are unreachable for these values.

## Selection and minimization

Selected complete main.qui lines: 2, 3, 4, 6. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 100 → 92; Task B 57 → 50. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.

Measurement: Task A 92; Task B 50. Tokenizer: metric/tokenizer.py, unchanged.
