# Task B selection — Kotlin

## Answer requirements shared across languages

1. Trace a zero-based top-down piece-frame cell into a one-based well column and upward-increasing row.
2. Identify bounds and storage indexing: valid columns 1..10 and rows 1..22, with row 20 visible and rows 21/22 hidden but still within bounds.
3. Distinguish out-of-well rejection and occupied-cell rejection from the visible/hidden-row test.

## Selected source locations

- `main.kt`: 81, 82, 83, 84, 85, 179, 196, 197, 198, 517

## Evidence and language semantics

The frame/shape coordinates feed the selected cell conversion: column = position.x + frame.x and row = position.y - frame.y, after any selected frame rotation. Thus increasing the frame row moves downward, whereas increasing the well row moves upward. Zero-based host arrays use row-1 and column-1 for storage; one-based array languages use their corresponding direct row index. The placement predicate rejects columns outside 1..10, rows outside 1..22, or occupied cells. The separate lock-out boundary at 21 (or greater than visible height 20) establishes the hidden rows: row 20 is below it, and 21/22 remain valid well cells; row 23 and row 0 fail the well bounds. Rotation details are included only where they occur between the named frame coordinate and the translation itself. 

## Minimization and alternatives

The excerpt retains the frame-coordinate origin when it is constructed from character indices, the translation, well bounds/storage lookup and the 20/21 boundary. Full shape strings, kick tables, movement search, line clearing, scores and print rendering cannot change those coordinate facts and are excluded. Taking fits alone would omit the top-down conversion and hidden boundary; taking cells alone would omit well validity. A single direct placement predicate is smaller than tracing callers. The lock-out test is used solely as evidence for the visible/hidden boundary, not as a claim that any single hidden cell immediately ends a game.

The excerpt contains 285 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
