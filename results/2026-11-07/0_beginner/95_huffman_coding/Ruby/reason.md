Swap only the traversal labels so left appends 1 and right appends 0. Frequencies and weight/minimum-symbol priority still construct the same tree, output symbols remain in ASCII order and every code length stays the same. The ASCII-space code changes from 110 to 001. Weighted encoded length remains 114 bits and fixed-eight-bit length remains 37*8=296 bits.

The tree sort/merge uses weight and minimum symbol independently of code text. Only the two visit calls change; counts*codes[symbol].length and text.length*8 explain unchanged totals.

Input frequency counting, priority ties, left/right tree construction, traversal labels and both bit totals establish why only code labels change. Printing codes alone would not establish unchanged weighted length.
