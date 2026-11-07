# Task B selection: 27_sieve_primes / Kotlin

Change physical allocation to limit+2 and translate all logical k accesses to k+1, leaving integer loop labels and inclusive limit 200 unchanged. Logical 0/1 flags move to 1/2, 7 to 8, composite 49 to 50 and 200 to 201. Apply this mapping to initialization, p tests, multiple marking and prime retrieval; output still uses logical labels in increasing order.

Only the sieve operation through retrieved prime values is required. Count reporting and ten-column presentation do not affect the offset contract.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6, 7, 8, 9. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
