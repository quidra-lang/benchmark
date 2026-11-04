# Task B selection: 15_gcd_lcm / Quidra

## Common answer requirements

Trace the source case (48, 180), its Euclidean remainders and termination, then connect the returned GCD to division before multiplication in the LCM.

## Source evidence

The declared pairs array and the destructuring loop bind 48 to a and 180 to b for this source case. The call passes both by value. The helper visits (48, 180), (180, 48), (48, 36), (36, 12), and (12, 0), returning 12 at termination. The caller still has the original pair and computes (48 / 12) × 180 = 720.

## Minimization

The pair declaration establishes the source input used by the call, as the combined input-and-loop line does in Python. The output label and unrelated display are unnecessary. Selected complete lines of `main.qui`: 1, 2, 3, 4, 6, 7, 8, 9.
