# Task B selection: 55_grid_paths / Swift

## Common answer requirements

Locate the path-count recurrence for both obstacle modes; explain adding the diagonal predecessor with bounds and destination-passability checks, allowing corner cutting and counting move sequences separately while retaining the two outputs.

## Supported analysis

For each passable destination, add the count at its upper-left predecessor when both coordinates are beyond their first row/column. This third summand counts a different final move from the top and left summands, so the three kinds of path sequence remain distinct. Keep the current destination obstacle guard outside all contributions; do not check the two orthogonally adjacent cells for a diagonal. Preserve the origin seed and row/column order. For a rolling one-dimensional DP, save the old dp[column] before overwriting it and carry the old previous-column value as the upper-left count, resetting that carried value at each row. Even when the current cell is blocked and reset to zero, preserve its old value for the next column diagonal. The selected state layout and recurrence identify which of these approaches this implementation needs.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.swift`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 15 | `for obstacles in [false, true] {` |
| 3 | 37 | `    var dp = [[Int]](repeating: [Int](repeating: 0, count: 7), count: 6)` |
| 4 | 13 | `    dp[0][0] = 1` |
| 5 | 13 | `    for r in 0..<6 {` |
| 6 | 14 | `        for c in 0..<7 {` |
| 7 | 25 | `            if obstacles && grid[r][c] == "#" {` |
| 8 | 16 | `                dp[r][c] = 0` |
| 9 | 6 | `                continue` |
| 10 | 5 | `            }` |
| 11 | 37 | `            if r > 0 { dp[r][c] += dp[r - 1][c] }` |
| 12 | 37 | `            if c > 0 { dp[r][c] += dp[r][c - 1] }` |
| 13 | 4 | `        }` |
| 14 | 3 | `    }` |
| 16 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **227 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 326 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 227 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
