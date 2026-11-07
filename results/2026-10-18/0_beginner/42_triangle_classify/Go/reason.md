# Task B selection: 42_triangle_classify / Go

Find the unsorted output operands and the sorted sides that can replace them; verify that the change covers invalid and valid inputs without changing their classification or sequence.

Keep the per-set classification and replace the output prefix's original side values with the already ascending sides. When the prefix is prepared before the sort, move its preparation after the sorted values become available. When a shared print follows classification, only its side operands need to change. Leave the result construction and outer traversal in place.

The sorting operations show where ascending values come from. Replacing only the common print operand or the prefix reused by both outcomes avoids changing any classifier. The validity test is needed when two distinct output sites consume the prefix. The input list is unnecessary unless its type establishes how the sorted copy is made.

The collection's element type is a three-element array, so assigning p to a copies the sides. Slicing a gives the sorter access to the copy.

Source: `main.go`, original lines 9–13. The previous excerpt measures 56 tokens; this evidence set measures 173 tokens.

## Current token measurement

Task A: **489 tokens**. Task B: **173 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
