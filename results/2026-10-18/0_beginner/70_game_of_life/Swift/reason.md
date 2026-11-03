# Task B selection: 70_game_of_life / Swift

## Common answer requirements

Trace generation-0 neighbors at zero-based (0,1) and (1,0), their generation-1 states, exclusion of out-of-board neighbors, and isolation of every count from earlier writes during that generation.

## Supported analysis

Cell (0,1) starts live and has only one live neighbor, at (1,2); its generation-1 state is dead. Cell (1,0) starts dead and has three live neighbors, at (0,1),(2,0),(2,1); it becomes live. Off-board coordinates are skipped, and the zero displacement excludes the cell itself. The old board is read for all neighbor counts and current-cell survival; next/following is distinct update storage, assigned/copied back only after the cell loops. Therefore the earlier computed death of (0,1) cannot remove that live neighbor while counting (1,0). Initial first-three-row data and the board conversion establish the concrete counts; other distant rows do not affect those neighborhoods.

Arrays have value semantics and next is separately constructed; the assignment follows all updates. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.swift`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 38 | `let initial = [".#......", "..#.....", "###.....", "........",` |
| 2 | 30 | `    "........", "........", ".....###", "........"]` |
| 3 | 32 | `var board = initial.map { $0.map { $0 == "#" } }` |
| 8 | 37 | `    var next = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 8)` |
| 9 | 13 | `    for r in 0..<8 {` |
| 10 | 14 | `        for c in 0..<8 {` |
| 11 | 11 | `            var neighbors = 0` |
| 12 | 16 | `            for dr in -1...1 {` |
| 13 | 17 | `                for dc in -1...1 {` |
| 14 | 27 | `                    if dr == 0 && dc == 0 { continue }` |
| 15 | 28 | `                    let nr = r + dr, nc = c + dc` |
| 16 | 57 | `                    if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr][nc] { neighbors += 1 }` |
| 17 | 6 | `                }` |
| 18 | 5 | `            }` |
| 19 | 39 | `            next[r][c] = neighbors == 3 \|\| (board[r][c] && neighbors == 2)` |
| 20 | 4 | `        }` |
| 21 | 3 | `    }` |
| 22 | 7 | `    board = next` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **384 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 503 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 386 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
