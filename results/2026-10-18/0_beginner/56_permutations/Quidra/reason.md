# Task B selection: 56_permutations / Quidra

## Common answer requirements

Trace the return from the last A-prefixed permutation to the first B-prefixed permutation, showing eligibility and numbering.

## Source evidence

The source enumerates A, B, C, D in that order. The last A-prefixed leaf is ADCB (#6). Returning drops B, C, D, then A as the exhausted frames unwind. The parent retains its prefix; the child receives a concatenated prefix, and the membership test makes discarded characters available as the shorter prefix is restored. Counts return through calls. The root then chooses B and the first available remaining choices are A, C, D. Reaching the length-four base case increments the count to 7 for BACD.

## Minimization

The initial call, choice and restore operations, and base-case counter update are necessary. A separate print statement does not explain how the leaf obtains its number; the excerpt retains output when it shares the increment line.

Selected complete lines of `main.qui`: 1–3, 5–10, 12. The prior excerpt measured 131 tokens; this excerpt measures 114 with `metric/tokenizer.py`.

Measurement: Task A 130; Task B 114. Tokenizer: metric/tokenizer.py, unchanged.
