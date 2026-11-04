# Task B selection — 43_run_length_encoding / Quidra

The second input has two runs of twelve W characters separated by one B. The documented text.runs operation reports maximal consecutive runs, so the encoder writes 12W1B12W3B. The decoder's cursor is constructed from the encoded string. Each take_nat consumes the complete count before take_char consumes the symbol. Repeating each symbol and appending the result reconstructs the original. The caller passes the encoded value to decode. Other fixture lines do not affect this trace.

Selected complete source lines in order are 1, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 19, 20, 21, 22.

Tokenizer: Task A 217 tokens; Task B 190 tokens.
