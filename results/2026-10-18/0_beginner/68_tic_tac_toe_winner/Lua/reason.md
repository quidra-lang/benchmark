# Task B selection: 68_tic_tac_toe_winner / Lua

## Common answer requirements

Trace board 6 and identify its recognized winning line; establish precedence of win over full-board status; compare board 4 no-win full-board draw behavior from the same control flow.

## Supported analysis

Board 6 is XOX/OXO/OXX. Its main diagonal (zero-based flattened cells 0,4,8) is XXX, so the win predicate recognizes X. The board is full, but the selected result flow either chooses the detected winner before testing emptiness, returns immediately on a winning line, or overwrites a provisional draw/in-progress result with the win. Therefore board 6 reports X wins. Board 4 is XOX/XOO/OXX; none of its rows, columns, or diagonals consists of three equal nonempty marks. It also has no dots, so the same winner-first/fallback control flow produces draw. The literals, all line definitions, equal-mark predicate, and result precedence are all source evidence required for that comparison.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 9 | `local function outcome(board)` |
| 2 | 26 | `    local lines = {board[1], board[2], board[3]}` |
| 3 | 14 | `    for column = 1, 3 do` |
| 4 | 54 | `        lines[#lines + 1] = board[1]:sub(column, column) .. board[2]:sub(column, column) .. board[3]:sub(column, column)` |
| 5 | 3 | `    end` |
| 6 | 53 | `    lines[#lines + 1] = board[1]:sub(1, 1) .. board[2]:sub(2, 2) .. board[3]:sub(3, 3)` |
| 7 | 53 | `    lines[#lines + 1] = board[1]:sub(3, 3) .. board[2]:sub(2, 2) .. board[3]:sub(1, 1)` |
| 8 | 17 | `    for _, line in ipairs(lines) do` |
| 9 | 18 | `        local first = line:sub(1, 1)` |
| 10 | 43 | `        if first ~= "." and line == string.rep(first, 3) then return first .. " wins" end` |
| 11 | 3 | `    end` |
| 12 | 37 | `    return table.concat(board):find(".", 1, true) and "in progress" or "draw"` |
| 13 | 2 | `end` |
| 15 | 8 | `local boards = {` |
| 16 | 80 | `    {"XXX", "OO.", "O.X"}, {"X.O", ".X.", "O.."}, {"XO.", ".OX", "XO."}, {"XOX", "XOO", "OXX"},` |
| 17 | 40 | `    {"X.O", "XO.", "O.X"}, {"XOX", "OXO", "OXX"},` |
| 19 | 49 | `for number, board in ipairs(boards) do io.write(string.format("board %d: %s\n", number, outcome(board))) end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **509 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 512 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 511 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
