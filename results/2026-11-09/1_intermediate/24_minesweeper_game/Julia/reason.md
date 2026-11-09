# Task B selection — Julia

## Answer requirements shared across languages

1. Locate the first-reveal SAFETY block exclusion and describe replacing its square-neighborhood test by a cell-plus-orthogonal-neighbors test, leaving cell/none branches unchanged.
2. Show that candidate construction visits in-board cells in row-major order and retains that order for the existing random-index selection/removal procedure.
3. Trace storage of a determined placement and the guard preventing later re-placement.
4. Establish that RESTART and UNDO restore play/history fields without clearing or recomputing determined mines.

## Selected source locations

- `main.jl`: 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 116, 117, 118, 119, 120, 121, 122, 123, 125, 126, 584, 585, 628, 629, 630, 631, 632, 633

## Evidence and language semantics

eachindex of the board mine vector gives ascending one-based linear cell IDs. Coordinate conversion explicitly subtracts one. Change only BLOCK filter to retain Manhattan distance greater than one; filter! and deleteat! keep survivor order. placed is set, reveal guards placement, and reset/UNDO preserve mines and placed.

## Minimization and alternatives

For block mode, retain exactly candidates with |dx|+|dy|>1; the loop already bounds every candidate to the board, so diagonals become eligible and edge/corner neighbors need no separate out-of-board insertion. The candidate-filter-only alternative is smaller but cannot establish the required unchanged random procedure or placement persistence. Including generic neighbor enumeration or flood-fill would be larger and could misleadingly suggest changing game adjacency; those operations are unaffected. Random constants and removal operations are retained where they are local to placement; recalculating adjacency numbers and all output formatting are omitted because they do not choose candidates or discard placement. Excerpt-only review confirms the four requirements from the filter, ordered construction/removal, storage/guard, and reset/undo mutation boundaries.

The excerpt contains 550 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
