# Task B selection: 56_permutations / Dart

## Common answer requirements

Trace the return from the last A-prefixed permutation to the first B-prefixed permutation, showing eligibility and numbering.

## Source evidence

The source enumerates A, B, C, D in that order. The last A-prefixed leaf is ADCB (#6). Returning drops B, C, D, then A as the exhausted frames unwind. The depth determines which shared word slots are active; shorter depth makes old suffix bytes irrelevant until overwritten. The post-call reset releases the marked choice. The root then chooses B and the first available remaining choices are A, C, D. Reaching the length-four base case increments the count to 7 for BACD.

## Minimization

The initial call, choice and restore operations, and base-case counter update are necessary. A separate print statement does not explain how the leaf obtains its number; the excerpt retains output when it shares the increment line.

Selected complete lines of `main.dart`: 2–6, 8–18, 20. The prior excerpt measured 214 tokens; this excerpt measures 193 with `metric/tokenizer.py`.
