# Task B selection: 42_triangle_classify / Kotlin

Find the unsorted output operands and the sorted sides that can replace them; verify that the change covers invalid and valid inputs without changing their classification or sequence.

Keep the per-set classification and replace the output prefix's original side values with the already ascending sides. When the prefix is prepared before the sort, move its preparation after the sorted values become available. When a shared print follows classification, only its side operands need to change. Leave the result construction and outer traversal in place.

The sorting operations show where ascending values come from. Replacing only the common print operand or the prefix reused by both outcomes avoids changing any classifier. The validity test is needed when two distinct output sites consume the prefix. The input list is unnecessary unless its type establishes how the sorted copy is made.

Both outputs use the same prefix, which currently precedes the ascending side preparation; move the prefix after that preparation.

Source: `main.kt`, original lines 7–10, 16. The previous excerpt measures 48 tokens; this evidence set measures 101 tokens.
