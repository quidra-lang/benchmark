# Task B selection: 87_gaussian_elimination / Quidra

## Answer requirements

After the first pivot swap in system 1, locate the expression that computes the multiplier for the next row before its column-1 entry is overwritten. Use coefficients 4 and 2 to explain why subsequent entry updates must reuse that captured factor rather than recomputing it from a changed entry. Focus on this local read-before-write dependency.

## Answer and source evidence

After the given swap, the next-row column-k entry is2 and pivot entry4, so factor is captured as2/4=0.5 before any entry is replaced. The j loop starts at k; its first update changes that numerator entry to0. Recomputing the factor afterward would incorrectly use0/4=0 for later columns. Every row update must reuse the stored factor; no other pivot or back-substitution evidence is needed.



Selected `main.qui` lines: 17, 18, 19, 20. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
