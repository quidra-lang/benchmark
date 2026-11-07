# Task B selection: 47_student_records / Kotlin

Locate the rank update and show how it can count distinct scores while leaving sorted iteration and output in place.

In a rank loop, start at zero and increment the rank once on the first student and once each time the total differs from the preceding total. Leave the rank unchanged within ties and retain the previous-total update where it exists. For a vectorized rank, assign each total the index of its match in the descending distinct totals. The example becomes 1, 2, 2, 3. Keep the existing sort, the average calculation and the output fields; the existing rank field will receive the new rank.

The current iteration, tie boundary and position-based assignment establish why a tie currently causes a skipped rank. Changing the assignment leaves the sorted order, average and formatting code untouched; those operations do not determine the edit.

Source: `main.kt`, original lines 11–15. The previous excerpt measures 55 tokens; this evidence set measures 78 tokens.

## Current token measurement

Task A: **372 tokens**. Task B: **77 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
