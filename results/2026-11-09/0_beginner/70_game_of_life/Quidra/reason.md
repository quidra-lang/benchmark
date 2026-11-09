# Task B selection: 70_game_of_life / Quidra

## Answer requirements

Explain the operation that derives one complete next generation from a current board. Identify cell traversal, neighbor-count construction, the live/dead decision and storage of the result, including how the corner at (0, 0) rejects a neighbor at (-1, 0) before access. Explain the actual guard evaluation and how newly computed cells cannot influence later neighbor counts. Stop after producing one next board rather than tracing all four generations.

## Answer and source evidence

Traverse each of the 8x8 cells and all offsets -1..1 except (0,0), counting live cells from the old board. At corner (0,0), offset (-1,0) fails the bounds conjunction before indexing, so negative coordinates are not accessed. A cell is live next iff it has three neighbors or is currently live with two. Build a separate row and next-board value, assigning board only after all cells finish; therefore new values never affect later old-generation neighbor counts. Printing and outer generation count are excluded.



Selected `main.qui` lines: 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
