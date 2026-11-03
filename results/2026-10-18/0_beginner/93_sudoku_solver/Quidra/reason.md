# Task B selection: 93_sudoku_solver / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Try candidate digits in descending order, 9 through 1, while keeping the same row-major choice of the next empty cell. Continue counting every successful write of a candidate digit, including writes later undone, and stop immediately when the first completed board is found. Retain the existing solved-board output and placements-line format; the placement count must reflect the new search order. All other Task A requirements remain unchanged.

## Source evidence and minimization

Change only this candidate range to 9 down through 1. The rest of the search, placement counting and first-solution exit are unchanged, so including those implementations would add no necessary modification evidence.

Locations in main source: L13.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 653; Task B 15. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
