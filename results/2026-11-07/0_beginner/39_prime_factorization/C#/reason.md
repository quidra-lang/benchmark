# Task B selection: 39_prime_factorization / C#

The final guard appends remaining only when it exceeds 1. For prime 9973, no trial factor is collected and remaining is still 9973, so this branch supplies that final prime; remaining=1 would fail the guard and add nothing.

The question gives the prime/no-collected-factor scenario. The guard and append alone establish this decision; divisor loops, complete input and output labels are outside scope.

Selected complete source lines in `Program.cs`: 21. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
