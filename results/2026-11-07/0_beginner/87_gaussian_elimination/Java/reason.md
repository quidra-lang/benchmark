# Task B selection: 87_gaussian_elimination / Java

The factor is captured before updates as a[i][k]/a[k][k], which is 2/4=0.5 after the first pivot swap. Updating column k then changes its numerator to zero; recomputing would incorrectly use zero for later columns. The stored factor is reused throughout the column loop.

The multiplier declaration and consuming update loop establish read-before-write order. Pivot selection/system data are unnecessary because the post-swap coefficients are given in the question.

Selected complete source lines in `Main.java`: 21, 22, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
