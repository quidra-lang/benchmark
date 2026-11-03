# Task B selection: 95_huffman_coding / Quidra

Identify the changes that reverse left/right bit labels on the completed Huffman tree while preserving tree priorities, symbol order and encoded lengths.

The two recursive calls append 0 on a left edge and 1 on a right edge. Exchanging those literals implements the requested labels. No tree construction, frequency or output changes are required; every code keeps its length, so the existing encoded-bit and fixed-width comparisons remain valid.

These are the only affected operations. A full traversal-function excerpt adds leaf handling and node access without identifying any further edit.

Selected complete source lines in order: 12, 13.

Every selected line is copied verbatim from `main.qui` in source order. The reviewed alternatives were the relevant contiguous span and complete source; each adds unchanged context. This is a reviewed sufficient selection, not a proof of a global minimum. Task B assumes Task A correctness as required by the benchmark README.

Task A uses 670 tokens. Task B uses 52 tokens under the unchanged `metric/tokenizer.py`. Source selection and token measurement do not establish compilation or execution.
