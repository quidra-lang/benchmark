# Task B selection: 01_sum_max_min / PHP

## Common answer requirements

1. Trace the contribution of -23 to the sum and the minimum for the actual array.
2. Explain why both occurrences of 5 contribute to addition, but duplicates do not change the minimum.

## Answer supported by the excerpt

The prefix 17, -8, 42, 5 has sum 56; adding -23 produces 33, and all ten elements sum to 92. The minimum before -23 is -8 and becomes -23, which no later value undercuts. Both array occurrences of 5 are visited or reduced, contributing 10 in total. Minimum selection compares values and does not accumulate multiplicities.

## Source evidence and dependencies

Selected `main.php` lines: 3-4. The excerpt preserves these complete lines in their original order and indentation.

The array line supplies the order, both 5 occurrences and all values needed to establish -23 as the final minimum. The selected addition and minimum reduction/update establish the two requested computations. Explicit loops also require initialization and traversal. Maximum-only updates are irrelevant and omitted unless inseparable on a retained line.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. A final output reference alone would not expose the data or accumulation. Conversely, where a standard aggregate directly establishes both statistics, separate getter/output lines add no fact required by this question. The data plus the actual reductions are the narrower sufficient alternative.

The selected excerpt contains **95 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 95 tokens; the complete source contains 100 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
