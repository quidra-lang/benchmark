# Task B selection — 43_run_length_encoding / Quidra

The second string contains two twelve-W runs separated by B, so the maximal adjacent runs returned by text.runs keep them separate. The encoder emits count then character. A cursor starts on the encoded string. take_nat consumes the whole digit prefix, including both digits of each 12, and take_char consumes the following symbol. Repeating that symbol and appending it reconstructs the input. The caller passes encoded to decode.

The library contracts explain run boundaries and numeric-prefix parsing, so the selection needs only their call sites. Including every fixture row would add unrelated inputs.

Selected complete source lines in order are 1, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 22, 23, 24.

Task A uses 253 tokens. Task B uses 242 tokens under the same benchmark tokenizer.
