# Task B source selection

## Common answer requirements

Identify live direction encoding/update and insertion point after the eleven board rows before black count, after 300 complete steps; specify U,R,D,L mapping and thirteen-line result.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Read the final direction state after the simulation loop, map 0,1,2,3 respectively to U,R,D,L using the movement-vector order, and insert one direction: D output immediately before the black-count output. The existing board-output loop has already printed eleven rows there. Do not insert inside the step or row loop. The extra line raises the output total to thirteen. No simulation logic needs changing.



## Source evidence and dependencies

The selected locations in `main.lua` are L6, L7, L8, L9, L15, L20, L22. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L6: `local row, column, direction = 5, 5, 0`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L7: `local directions = {{-1, 0}, {0, 1}, {1, 0}, {0, -1}}`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L8: `for _ = 1, 300 do`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L9: `direction = (direction + (board[row][column] and -1 or 1)) % 4`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L15: `for r = 0, 10 do`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L20: `io.write("\n")`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L22: `io.write(string.format("black: %d\n", black))`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **218 tokens** for the final selected lines. The prior candidate measured 158 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final original source lines: L6, L7, L8, L9, L11, L12, L13, L15, L20, L21, L22.
- L11: `    row = (row + directions[direction + 1][1]) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L12: `    column = (column + directions[direction + 1][2]) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L13: `end` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L21: `end` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final selection: 218 metric tokens; contiguous span L6–L22: 340 tokens; complete source: 405 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
