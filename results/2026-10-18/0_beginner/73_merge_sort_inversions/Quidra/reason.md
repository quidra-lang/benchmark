# Task B selection: 73_merge_sort_inversions / Quidra

## Common answer requirements

Identify merge-trace emission and the accumulator that counts through each completed merge, preserving the final summary format.

## Supported analysis

Append the cumulative count before the existing trace newline. A subtree-local return count can stay as it is for the summary; carry a separate accumulator initialized at the outer call and update it at each inversion increment, without adding child counts again. If the recursion already shares or threads the running count, use that same count. Both child calls precede the parent trace, so the accumulator includes previous merges.

The excerpt is copied verbatim from `main.qui`, in source order. Retained source lines: 3, 4, 5, 6, 7, 8, 21, 24, 27, 28.

## Minimization and alternatives

The recursive calls, count increment and trace are a smaller alternative to retaining the entire merge routine. Sorted-array copying and final summary formatting do not affect the count shown on trace lines. The prior selection used 182 tokens; this selection uses 176 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 447; Task B 176.

Measurement: Task A 447; Task B 176. Tokenizer: metric/tokenizer.py, unchanged.
