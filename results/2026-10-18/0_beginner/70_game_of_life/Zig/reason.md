# Task B selection: 70_game_of_life / Zig

## Common answer requirements

Trace generation-0 neighbors at zero-based (0,1) and (1,0), their generation-1 states, exclusion of out-of-board neighbors, and isolation of every count from earlier writes during that generation.

## Supported analysis

Cell (0,1) starts live and has only one live neighbor, at (1,2); its generation-1 state is dead. Cell (1,0) starts dead and has three live neighbors, at (0,1),(2,0),(2,1); it becomes live. Off-board coordinates are skipped, and the zero displacement excludes the cell itself. The old board is read for all neighbor counts and current-cell survival; next/following is distinct update storage, assigned/copied back only after the cell loops. Therefore the earlier computed death of (0,1) cannot remove that live neighbor while counting (1,0). Initial first-three-row data and the board conversion establish the concrete counts; other distant rows do not affect those neighborhoods.

next is a separate fixed array; every next[r][c] is assigned while all counts read board, then board=next copies the completed generation. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 7 | 16 | `    const initial = [_][]const u8{` |
| 8 | 10 | `        ".#......",` |
| 9 | 10 | `        "..#.....",` |
| 10 | 10 | `        "###.....",` |
| 16 | 4 | `    };` |
| 17 | 19 | `    var board: [8][8]bool = undefined;` |
| 18 | 15 | `    for (0..8) \|r\| {` |
| 19 | 14 | `        for (0..8) \|c\|` |
| 20 | 28 | `            board[r][c] = initial[r][c] == '#';` |
| 21 | 3 | `    }` |
| 31 | 20 | `        var next: [8][8]bool = undefined;` |
| 32 | 16 | `        for (0..8) \|r\| {` |
| 33 | 17 | `            for (0..8) \|c\| {` |
| 34 | 16 | `                var count: u32 = 0;` |
| 35 | 17 | `                var dr: i32 = -1;` |
| 36 | 26 | `                while (dr <= 1) : (dr += 1) {` |
| 37 | 18 | `                    var dc: i32 = -1;` |
| 38 | 27 | `                    while (dc <= 1) : (dc += 1) {` |
| 39 | 24 | `                        if (dr == 0 and dc == 0)` |
| 40 | 10 | `                            continue;` |
| 41 | 31 | `                        const rr = @as(i32, @intCast(r)) + dr;` |
| 42 | 31 | `                        const cc = @as(i32, @intCast(c)) + dc;` |
| 43 | 60 | `                        if (rr >= 0 and rr < 8 and cc >= 0 and cc < 8 and board[@intCast(rr)][@intCast(cc)])` |
| 44 | 14 | `                            count += 1;` |
| 45 | 7 | `                    }` |
| 46 | 6 | `                }` |
| 47 | 41 | `                next[r][c] = count == 3 or (board[r][c] and count == 2);` |
| 48 | 5 | `            }` |
| 49 | 4 | `        }` |
| 50 | 9 | `        board = next;` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **528 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 902 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 537 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
