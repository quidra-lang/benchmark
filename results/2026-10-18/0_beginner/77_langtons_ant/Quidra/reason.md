# Task B source selection

## Common answer requirements

Identify live direction encoding/update and insertion point after the eleven board rows before black count, after 300 complete steps; specify U,R,D,L mapping and thirteen-line result.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Read the final direction state after the simulation loop, map 0,1,2,3 respectively to U,R,D,L using the movement-vector order, and insert one direction: D output immediately before the black-count output. The existing board-output loop has already printed eleven rows there. Do not insert inside the step or row loop. The extra line raises the output total to thirteen. No simulation logic needs changing.



## Source evidence and dependencies

The selected locations in `main.qui` are L4, L5, L6, L7, L8, L13, L19, L20. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L4: `int direction = 0`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L5: `int[] dr = [-1, 0, 1, 0]`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L6: `int[] dc = [0, 1, 0, -1]`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L7: `for 0 <= int step < 300`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L8: `direction = if black[row][column] then (direction + 3) % 4 else (direction + 1) % 4`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L13: `for 0 <= int r < 11`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L19: `print(line + NL)`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L20: `print("black: {count}{NL}")`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **201 tokens** for the final selected lines. The prior candidate measured 149 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final original source lines: L4, L5, L6, L7, L8, L10, L11, L13, L19, L20.
- L10: `    row = (row + dr[direction] + 11) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L11: `    column = (column + dc[direction] + 11) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final selection: 201 metric tokens; contiguous span L4–L20: 327 tokens; complete source: 375 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
