# Task B selection: 15_gcd_lcm / Kotlin

Euclid changes (48,180) to (180,48), (48,36), (36,12), then (12,0), with remainders 48,36,12,0. The zero second working value terminates the loop and returns 12. Signed integer working storage admits zero and no positivity runtime check is present; positivity of this result follows from these inputs and the arithmetic, not a positive-only static type.

The gcd signature and complete arithmetic/return path suffice because the arguments are supplied in the question. Caller iteration, lcm and presentation are outside the requested operation.

Selected complete source lines in `main.kt`: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
