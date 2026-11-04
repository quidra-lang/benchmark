# Task B selection: 63_word_search / TypeScript

## Common answer requirements

Select the last valid match in the same row-major and direction order; preserve the match test and per-word result/fallback format.

## Source evidence

The row-major loops and direction traversal show the unchanged order. Replace the first-match return with assignment to a result initialized to the fallback, and return it after all loops. Every valid match replaces the saved value. Keep the per-word result format.

## Minimization

Board literals and the character checks do not change unless the checks share the retained success branch. The loop order, success handling, and fallback identify where to make the change; a helper’s caller already consumes the same result type and format.

Selected complete lines of `main.ts`: 5–10, 12–15, 20–24. The prior excerpt measured 346 tokens; this excerpt measures 344 with `metric/tokenizer.py`.
