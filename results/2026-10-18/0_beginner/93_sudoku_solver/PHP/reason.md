# Task B selection: 93_sudoku_solver / PHP

## Common answer requirements

Locate candidate-digit order and change it to 9 through 1; preserve row-major empty-cell choice, count every successful write including backtracks, and stop at first solved board.

## Answer and source dependencies

Change the candidate-digit enumeration from1through9 to9through1, retaining both endpoints. Existing row-major empty-cell selection, validity processing, placement increment after each successful write, recursion and undo already respond to that enumeration and need no edits. Do not hardcode the new count or alter output. For the unsigned Zig countdown, initialize9, decrement and stop at0 before underflow. The excerpt identifies precisely the affected enumeration, while the unchanged recursive body is a larger sufficient alternative that contributes no additional edit requirement.



## Scope and dependency evidence checked after independent review

Only candidate enumeration changes; the current increasing bound/start/step is the affected site. Reverse it to9through1, preserving the unchanged cell choice, validity test, successful-write counter, recursive first-solution stop and undo.

Source: `main.php`. Selected original locations: L39.

- L39: `                for ($digit = 1; $digit <= 9; $digit++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **30 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 120 tokens. The contiguous original span L39–L39 costs 30 tokens; the complete original source costs 822 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L39: 0 tokens; removes `for ($digit = 1; $digit <= 9; $digit++) {` from the dependency chain described above.
