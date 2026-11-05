# Task B selection: 41_quadratic_roots / Quidra

Derive the discriminant and both formula values for the supplied coefficients, then trace the larger value into the printed x1 field.

The discriminant is 57. With denominator −4, the plus-square-root numerator produces (5 − √57)/4 ≈ −0.6375, and the minus-square-root numerator produces (5 + √57)/4 ≈ 3.1375. Because the negative denominator reverses their order, the comparison and swap or max/min operations put 3.1375 in x1 and −0.6375 in x2. The print arguments or interpolations retain that association.

The tuple is supplied by the question, so the other coefficient sets and unrelated real/complex branches do not supply evidence. The positive-discriminant branch, numeric root operations and field mapping are retained. A custom formatter is retained only where its behavior is needed to connect a root to the corresponding printed field.

The swap moves the greater value into the first output argument after both roots have been evaluated.

Source: `main.qui`, original lines 1, 5–7, 9–15. The previous excerpt measures 191 tokens; this evidence set measures 170 tokens.

Measurement: Task A 447; Task B 170. Tokenizer: metric/tokenizer.py, unchanged.
