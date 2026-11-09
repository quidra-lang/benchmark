For arguments (48,180), successive remainders are 48,36,12,0; the working pairs become (180,48),(48,36),(36,12),(12,0). The zero second value stops iteration and the result is 12. Zero is necessary as the termination remainder; positive input remainders leave a positive returned gcd.

The parameters, temporary r and return have int behavior, which permits zero and signed values. Explicit assignment first saves a%b, then rotates a,b; no positivity refinement is enforced.

The working-pair assignment, remainder loop condition and return establish every Euclidean step. The LCM expression and other examples are independent of this GCD trace.
