# Task B selection — 93_sudoku_solver / Quidra

## Common answer requirements

Locate the candidate enumeration and reverse it to 9 through 1. Keep the next-cell choice, successful-write count, backtracking and first-solution termination.

## Source evidence

The typed range has inclusive bounds 1 and 9. Reverse the bounds and comparison direction to enumerate 9 down to 1, using the default descending integer step.

## Minimization

Selected complete lines of `main.qui`: L13. The change affects only the enumeration. The wider recursive body, puzzle data and output would provide context about unchanged behavior but do not locate any other edit.

The selected excerpt measures **14 tokens** with `metric/tokenizer.py`.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 605; Task B 14.

Measurement: Task A 605; Task B 14. Tokenizer: metric/tokenizer.py, unchanged.
