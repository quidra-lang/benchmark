# Task B selection: 64_spiral_matrix / Lua

## Common answer requirements

Trace positions and direction from writing 6 through 12; identify the first occupied-cell turn, explain next-cell boundary/occupancy checks and clockwise direction selection, and explain termination immediately after writing 30.

## Supported analysis

Using zero-based row,column, 6 is written at (0,5); the proposed east cell is outside the six columns, so the direction becomes south. Values 7,8,9,10 occupy (1,5),(2,5),(3,5),(4,5); the next south cell is outside the five rows, so turn west. Values 11 and 12 occupy (4,4),(4,3). Continuing the outer rim gives 15 at (4,0) and then 16,17,18 at (3,0),(2,0),(1,0). After 18 the proposed (0,0) contains 1: this is the first turn caused by an already-filled cell, so turn east to write 19 at (1,1). The direction table is east,south,west,north and increment modulo four chooses clockwise. The zero initialization, occupancy test, and sequential writes justify the occupied-cell trace. The explicit final-value break happens after writing 30 and before proposing another cell, so no further writable cell is required.

The table and direction indexes are one-based; the same trace is shifted by one. Bounds are tested before table access via or short-circuiting. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 9 | `local matrix = {}` |
| 2 | 13 | `for row = 1, 5 do` |
| 3 | 11 | `    matrix[row] = {}` |
| 4 | 28 | `    for column = 1, 6 do matrix[row][column] = 0 end` |
| 5 | 2 | `end` |
| 6 | 41 | `local directions = {{0, 1}, {1, 0}, {0, -1}, {-1, 0}}` |
| 7 | 20 | `local row, column, direction = 1, 1, 1` |
| 8 | 14 | `for value = 1, 30 do` |
| 9 | 13 | `    matrix[row][column] = value` |
| 10 | 16 | `    if value == 30 then break end` |
| 11 | 20 | `    local dr, dc = table.unpack(directions[direction])` |
| 12 | 23 | `    local r, c = row + dr, column + dc` |
| 13 | 49 | `    if r < 1 or r > 5 or c < 1 or c > 6 or matrix[r][c] ~= 0 then` |
| 14 | 16 | `        direction = direction % 4 + 1` |
| 15 | 19 | `        dr, dc = table.unpack(directions[direction])` |
| 16 | 3 | `    end` |
| 17 | 21 | `    row, column = row + dr, column + dc` |
| 18 | 2 | `end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **320 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 387 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 322 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
