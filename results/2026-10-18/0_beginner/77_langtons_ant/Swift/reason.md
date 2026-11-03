# Task B source selection

## Common answer requirements

Identify live direction encoding/update and insertion point after the eleven board rows before black count, after 300 complete steps; specify U,R,D,L mapping and thirteen-line result.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Read the final direction state after the simulation loop, map 0,1,2,3 respectively to U,R,D,L using the movement-vector order, and insert one direction: D output immediately before the black-count output. The existing board-output loop has already printed eleven rows there. Do not insert inside the step or row loop. The extra line raises the output total to thirteen. No simulation logic needs changing.



## Source evidence and dependencies

The selected locations in `main.swift` are L2, L3, L4, L5, L10, L15, L17. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L2: `var r = 5, c = 5, direction = 0`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L3: `let dr = [-1, 0, 1, 0], dc = [0, 1, 0, -1]`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L4: `for _ in 0..<300 {`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L5: `direction = (direction + (black[r][c] ? 3 : 1)) % 4`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L10: `for row in 0..<11 {`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L15: `print(line)`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.
- L17: `print("black: \(black.joined().filter { $0 }.count)")`. This line supplies the direction encoding/update, simulation bound or board/count output boundary; together they locate the new line after the board and map the live direction to its required letter.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **210 tokens** for the final selected lines. The prior candidate measured 154 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final original source lines: L2, L3, L4, L5, L7, L8, L9, L10, L15, L16, L17.
- L7: `    r = (r + dr[direction] + 11) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L8: `    c = (c + dc[direction] + 11) % 11` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L9: `}` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.
- L16: `}` — Indexed movement connects the final direction variable to its row/column displacement, establishing0=U,1=R,2=D,3=L (with the shown one-based adjustment where applicable). Simulation and board-row completion identify the insertion point after300 complete steps and all11 rows, before black count.

Final selection: 210 metric tokens; contiguous span L2–L17: 297 tokens; complete source: 335 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
