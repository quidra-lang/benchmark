# Task B selection — Python

## Answer requirements shared across languages

1. Locate the first-reveal SAFETY block exclusion and describe replacing its square-neighborhood test by a cell-plus-orthogonal-neighbors test, leaving cell/none branches unchanged.
2. Show that candidate construction visits in-board cells in row-major order and retains that order for the existing random-index selection/removal procedure.
3. Trace storage of a determined placement and the guard preventing later re-placement.
4. Establish that RESTART and UNDO restore play/history fields without clearing or recomputing determined mines.

## Selected source locations

- `main.py`: 168, 177, 178, 179, 180, 181, 182, 183, 213, 214, 215, 216, 218, 219, 224, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 578, 579, 580, 612, 613, 614, 675, 676, 677, 678, 679, 680

## Evidence and language semantics

The ascending range and width-based coordinates establish row-major order. Change allowed only in the block branch to abs(dx)+abs(dy)>1. list.pop(index) selects and removes while preserving survivor order. set_mines marks placement complete; open_cell guards it. restart and restore do not change mines or placed.

## Minimization and alternatives

For block mode, retain exactly candidates with |dx|+|dy|>1; the loop already bounds every candidate to the board, so diagonals become eligible and edge/corner neighbors need no separate out-of-board insertion. The candidate-filter-only alternative is smaller but cannot establish the required unchanged random procedure or placement persistence. Including generic neighbor enumeration or flood-fill would be larger and could misleadingly suggest changing game adjacency; those operations are unaffected. Random constants and removal operations are retained where they are local to placement; recalculating adjacency numbers and all output formatting are omitted because they do not choose candidates or discard placement. Excerpt-only review confirms the four requirements from the filter, ordered construction/removal, storage/guard, and reset/undo mutation boundaries.

The excerpt contains 669 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
