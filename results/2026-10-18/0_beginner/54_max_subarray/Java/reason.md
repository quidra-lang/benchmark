# Task B selection: 54_max_subarray / Java

## Common answer requirements

Trace array 2 through 10 and −2, including the restart/extend decision and preservation of the recorded best range.

## Source evidence

In array 2, initialize at −4, restart at 7 because the preceding candidate sum is negative, then extend through −1, 3, and −8 to candidate sums 6, 9, and 1. Extend with 10 to 11, then with −2 to 9. The best total becomes 11 at the 10, copying the candidate start into the separate range [1,5] in the source’s indexing. The next candidate fails the strict improvement test, so the stored range is unchanged.

## Minimization

Data through the second array and the candidate and best updates are necessary. Output and independent third-array data do not participate; a trailing delimiter does not govern any further retained step.

Selected complete lines of `Main.java`: 3–5, 7–19. The prior excerpt measured 409 tokens; this excerpt measures 335 with `metric/tokenizer.py`.
