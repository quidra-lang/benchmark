# Task B selection for 92_bst_traversal

The insertion order and search branches establish the subtree before
deletion. Removing 6 leaves 13 to the left of 27. Deleting 27 calls
`BinaryNodes.detach_leftmost` on the subtree rooted at 39. The documented
operation follows left links, returns 31 and reconnects 31's right child 34
at its former position. The caller replaces the target value with 31,
assigns the remaining subtree rooted at 39 to its right, and writes the
updated node back to the store. Thus 31 has left child 13 and right child 39,
whose left child is 34. The final calls visit the replacement before its
descendants and compute the height from the updated root.

The selection keeps construction, both removals, and the final traversal
and height calls. It excludes the initial output and the formatting helper.
The documented Collections operations establish traversal order, height,
and the successor splice without requiring their implementations.

Selected complete lines in order are 1, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 47, 48, 53, 54, 55, 56, 61, 62, 63, 64.
Task A uses 871 tokens. Task B uses 731 tokens.
