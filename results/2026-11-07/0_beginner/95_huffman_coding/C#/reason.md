# Task B selection: 95_huffman_coding / C#

Frequency and (weight,minimum-symbol) queue priority build the same tree; dequeued left/right children stay unchanged. Swap only traversal bit labels, complementing every code without changing lengths or ASCII frequency order. Space currently has code 110 and becomes 001; its frequency is 7. Encoded total remains 114 bits and fixed-eight-bit total remains 296 because both depend on counts/lengths, not bit values.

The actual text, frequency/tree/comparator/child/code/output chain and node field contract are all necessary for space code and total consequences. Wrappers/imports add no evidence.

Selected complete source lines in `Program.cs`: 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 45. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
