# Task B selection: 58_morse_code / Quidra

## Answer requirements

Identify reconstruction from generated Morse text, trace ME to AT separator boundaries, show where generated codes supply letters/spaces, and explain independence from original message reads.

## Answer supported by the selected source

At the ME/AT boundary, encoding makes -- . / .- -. The single spaces join codes inside words; the space-slash-space join separates words. Reconstruction splits encoded at that three-character separator, splits each resulting word at a single space, finds each symbol in codes, and indexes alphabet at that position. Joining letters with an empty separator produces ME and AT; the final single-space word join supplies their boundary. The original message is read only on the encoding path. index_of is fully evidenced by its return of collections.index, whose documented semantics return the matching position or an error; the success-only nat return applies the contextual fail-fast rule.

## Evidence and alternatives

The import and lookup implementation are needed because its name and return type alone do not establish lookup behavior. The tables, message and codepoint conversion establish correspondence and generated data. Encoding joins and decoding splits/joins establish the two separator levels. Final word joining is in the output expression and is therefore retained. Separate mutable accumulation loops were considered; typed generation expresses the same ordered transformations with fewer tokens. Neither the helper body nor the word-joining print may be omitted merely by assuming their behavior.

Selected complete main.qui source lines: 1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 4edefba77b30a2a7d55e2849f30e2d022fb1f6b2d12d7319f45293830459555a): Task A 491 tokens; Task B 489 tokens. Original values: Task A 489; Task B 487. Task B proposed modifications have not been implemented. Native validation of Task A is recorded separately in validation-results.json; lexical counts or excerpt review do not by themselves establish compilation or correctness.
