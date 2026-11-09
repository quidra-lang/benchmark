# Task B selection: 95_huffman_coding / Python

## Answer requirements

Suppose left-child moves receive bit 1 and right-child moves bit 0. Explain the complete path from the supplied string through frequencies, tree-priority selection, child construction, code traversal and output under this change. Identify where only the bit labels change and why the tree, frequency order and code lengths do not. Derive the new code for ASCII space and explain the consequences for encoded-bit and fixed-eight-bit totals, citing the actual counting and output operations.

## Answer and source evidence

Change only traversal bit labels: append1 for a left child and0 for a right child. Frequencies and (weight,smallest-symbol) priority still construct the same tree and left/right child identities, so every code length and output symbol order stays unchanged. ASCII space has original path right,right,left (110), hence new code001. Frequency-weighted code lengths still total114 encoded bits; source length37 still gives296 fixed-eight-bit bits. The selected frequency, priority, construction, traversal and counting/output stages establish this full path; the new labels do not require rebuilding with a different priority.



Selected `main.py` lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
