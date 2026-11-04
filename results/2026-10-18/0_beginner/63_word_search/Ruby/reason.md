# Task B selection: 63_word_search / Ruby

## Common answer requirements

Select the last valid match in the same row-major and direction order; preserve the match test and per-word result/fallback format.

## Source evidence

Keep assigning the formatted match to found, but remove the inner break and both outer break-if-found tests. The final fallback returns the last saved result or “not found”. The row, column and direction loops stay in the same order.

## Minimization

Board literals and the character checks do not change unless the checks share the retained success branch. The loop order, success handling, and fallback identify where to make the change; a helper’s caller already consumes the same result type and format.

Selected complete lines of `main.rb`: 5–7, 9–13, 18–27. The prior excerpt measured 266 tokens; this excerpt measures 264 with `metric/tokenizer.py`.
