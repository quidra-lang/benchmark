# Task B selection — C

## Answer requirements shared across languages

1. Locate the first-reveal SAFETY block exclusion and describe replacing its square-neighborhood test by a cell-plus-orthogonal-neighbors test, leaving cell/none branches unchanged.
2. Show that candidate construction visits in-board cells in row-major order and retains that order for the existing random-index selection/removal procedure.
3. Trace storage of a determined placement and the guard preventing later re-placement.
4. Establish that RESTART and UNDO restore play/history fields without clearing or recomputing determined mines.

## Selected source locations

- `main.c`: 112, 133, 134, 135, 136, 137, 138, 139, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 186, 190, 191, 607, 608, 646, 647, 648, 649, 650, 651, 654

## Evidence and language semantics

The linear cell loop converts coordinates by width and the BLOCK disjunction is the replacement site. memmove preserves the order of unselected candidates. determined is set once; restart and the UNDO field copies omit mines/determined.

## Minimization and alternatives

For block mode, retain exactly candidates with |dx|+|dy|>1; the loop already bounds every candidate to the board, so diagonals become eligible and edge/corner neighbors need no separate out-of-board insertion. The candidate-filter-only alternative is smaller but cannot establish the required unchanged random procedure or placement persistence. Including generic neighbor enumeration or flood-fill would be larger and could misleadingly suggest changing game adjacency; those operations are unaffected. Random constants and removal operations are retained where they are local to placement; recalculating adjacency numbers and all output formatting are omitted because they do not choose candidates or discard placement. Excerpt-only review confirms the four requirements from the filter, ordered construction/removal, storage/guard, and reset/undo mutation boundaries.

The excerpt contains 715 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
