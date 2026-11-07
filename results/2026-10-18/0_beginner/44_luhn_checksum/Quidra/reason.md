# Task B selection — 44_luhn_checksum / Quidra

The fixture is a string, so its leading zero survives indexing and printing. Only each indexed character is parsed. The left-to-right zero-based index i maps to right-based position `#number - i`, so even positions are doubled, with 9 subtracted from doubled digits above 9. A nonzero residue enters the invalid branch. Subtracting the last digit from the total leaves the prefix contribution, and (10 - prefix % 10) % 10 gives the replacement. The total is 42, and the prefix contribution is 38, so the original number is printed unchanged with replacement digit 2. The other fixture values are irrelevant to the trace.

Selected complete source lines in order are 1, 3, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23.

Tokenizer: Task A 337 tokens; Task B 224 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 337; Task B 224.

Measurement: Task A 337; Task B 224. Tokenizer: metric/tokenizer.py, unchanged.
