# Task B selection: 70_game_of_life / Lua

## Common answer requirements

Trace generation-0 neighbors at zero-based (0,1) and (1,0), their generation-1 states, exclusion of out-of-board neighbors, and isolation of every count from earlier writes during that generation.

## Supported analysis

Cell (0,1) starts live and has only one live neighbor, at (1,2); its generation-1 state is dead. Cell (1,0) starts dead and has three live neighbors, at (0,1),(2,0),(2,1); it becomes live. Off-board coordinates are skipped, and the zero displacement excludes the cell itself. The old board is read for all neighbor counts and current-cell survival; next/following is distinct update storage, assigned/copied back only after the cell loops. Therefore the earlier computed death of (0,1) cannot remove that live neighbor while counting (1,0). Initial first-three-row data and the board conversion establish the concrete counts; other distant rows do not affect those neighborhoods.

Following rows are newly allocated tables, distinct from board rows. Requested zero-based cells map to [1][2] and [2][1]. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 67 | `local initial = {".#......", "..#.....", "###.....", "........", "........", "........", ".....###", "........"}` |
| 2 | 9 | `local board = {}` |
| 3 | 13 | `for row = 1, 8 do` |
| 4 | 11 | `    board[row] = {}` |
| 5 | 44 | `    for column = 1, 8 do board[row][column] = initial[row]:sub(column, column) == "#" end` |
| 6 | 2 | `end` |
| 14 | 10 | `    local following = {}` |
| 15 | 14 | `    for row = 1, 8 do` |
| 16 | 12 | `        following[row] = {}` |
| 17 | 15 | `        for column = 1, 8 do` |
| 18 | 11 | `            local neighbors = 0` |
| 19 | 17 | `            for dr = -1, 1 do` |
| 20 | 18 | `                for dc = -1, 1 do` |
| 21 | 27 | `                    local r, c = row + dr, column + dc` |
| 22 | 67 | `                    if (dr ~= 0 or dc ~= 0) and r >= 1 and r <= 8 and c >= 1 and c <= 8 and board[r][c] then` |
| 23 | 16 | `                        neighbors = neighbors + 1` |
| 24 | 7 | `                    end` |
| 25 | 6 | `                end` |
| 26 | 5 | `            end` |
| 27 | 39 | `            following[row][column] = neighbors == 3 or (board[row][column] and neighbors == 2)` |
| 28 | 4 | `        end` |
| 29 | 3 | `    end` |
| 30 | 7 | `    board = following` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **424 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 637 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 434 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
