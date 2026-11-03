# Task B selection: 51_case_converter / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Extend the conversion to produce a fifth form called upper, made by converting every normalized word entirely to ASCII uppercase and joining the words with underscores. Append ", upper=U" to each existing output line, where U is that form, using the same comma-and-space convention as the other fields. Derive it from the same word splitting rules, including discarded empty parts. All other Task A requirements remain unchanged.

## Source evidence and minimization

Reuse snake.upper_ascii() for the fifth output: text.identifier.snake normalizes the same ASCII words, discards empty parts and joins with underscores. The Text import establishes this library binding. The existing full output line identifies where to append the new field. Re-reading the other three unchanged conversions or the library implementation adds no necessary evidence.

Locations in main source: L1, L8, L12.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 179; Task B 59. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
