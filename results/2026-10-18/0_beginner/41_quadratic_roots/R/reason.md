# Task B selection: 41_quadratic_roots / R

Derive the discriminant and both formula values for the supplied coefficients, then trace the larger value into the printed x1 field.

The discriminant is 57. With denominator −4, the plus-square-root numerator produces (5 − √57)/4 ≈ −0.6375, and the minus-square-root numerator produces (5 + √57)/4 ≈ 3.1375. Because the negative denominator reverses their order, the comparison and swap or max/min operations put 3.1375 in x1 and −0.6375 in x2. The print arguments or interpolations retain that association.

The tuple is supplied by the question, so the other coefficient sets and unrelated real/complex branches do not supply evidence. The positive-discriminant branch, numeric root operations and field mapping are retained. A custom formatter is retained only where its behavior is needed to connect a root to the corresponding printed field.

Source: `main.R`, original lines 6, 8–11. The previous excerpt measures 288 tokens; this evidence set measures 139 tokens.
