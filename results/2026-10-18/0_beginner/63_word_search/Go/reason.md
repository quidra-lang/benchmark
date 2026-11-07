# Task B selection: 63_word_search / Go

## Common answer requirements

Select the last valid match in the same row-major and direction order; preserve the match test and per-word result/fallback format.

## Source evidence

The row, column and direction loops identify the traversal. The success branch currently emits a result and stops by a break or a flag-controlled outer condition. Replace that early output with a saved latest match for the word, remove the search termination only, and print the saved coordinates and direction after the whole grid, or the fallback when nothing was saved.

## Minimization

Board literals and the character checks do not change unless the checks share the retained success branch. The loop order, success handling, and fallback identify where to make the change; a helper’s caller already consumes the same result type and format.

Selected complete lines of `main.go`: 8, 11–14, 23–32. The prior excerpt measured 273 tokens; this excerpt measures 269 with `metric/tokenizer.py`.

## Current token measurement

Task A: **629 tokens**. Task B: **269 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
