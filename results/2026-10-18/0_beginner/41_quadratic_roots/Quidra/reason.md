# Task B selection: 41_quadratic_roots / Quidra

## Common answer requirements

Trace coefficients (-2,5,4), the discriminant and formula results, larger-root ordering despite negative a, and printed x1/x2 fields.

## Source evidence and minimization

Task B supplies the coefficients; the typed destructuring loop establishes their a/b/c roles and integer types. The full input collection adds no required information. The discriminant is 57; the formula produces approximately -0.6374586 and 3.1374586. The selected comparison and tuple swap place the larger result in first, and the selected print preserves first as x1 and second as x2. The typed real64 denominator/numerator/root/result bindings preserve the numerical contract. The unchanged zero/complex branches are unnecessary for this positive-discriminant trace.

Selected original source lines: L1, L4, L5, L6, L7, L9, L10, L11, L12, L13, L14, L15.
Every selected line is complete, verbatim and in source order. Alternative complete
source and contiguous-context selections retain unrelated information; the removed
input records or independent operations add no required fact. This is a reviewed
sufficient minimized candidate, not a proof of a global mathematical minimum.
Language and documented library semantics are available as prior knowledge.

Task B: 199 tokens under the unchanged metric/tokenizer.py. Task A is unchanged
by this evidence correction.
