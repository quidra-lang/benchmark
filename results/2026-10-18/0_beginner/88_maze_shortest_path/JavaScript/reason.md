# Task B selection: 88_maze_shortest_path / JavaScript

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.js`. Selected original locations: L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32.

- L5: `const height = rows.length, width = rows[0].length;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `const maze = rows.join("").split("");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `const start = maze.indexOf("S"), goal = maze.indexOf("G");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `const parent = Array(maze.length).fill(-1), queue = [start];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `parent[start] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `for (let head = 0; head < queue.length; head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  const cell = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  if (cell === goal) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  const row = Math.floor(cell / width), column = cell % width;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    const r = row + dr, c = column + dc;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    if (r >= 0 && r < height && c >= 0 && c < width) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `      const neighbor = r * width + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      if (maze[neighbor] !== "#" && parent[neighbor] < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        parent[neighbor] = cell;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        queue.push(neighbor);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `let steps = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `for (let cell = goal; cell !== start; cell = parent[cell]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `  steps++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `  if (maze[cell] === ".") maze[cell] = "*";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `console.log(`steps: ${steps}`);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `for (let offset = 0; offset < maze.length; offset += width) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  console.log(maze.slice(offset, offset + width).join(""));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **542 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 323 tokens. The contiguous original span L5–L32 costs 542 tokens; the complete original source costs 655 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 520 tokens; removes `const height = rows.length, width = rows[0].length;` from the dependency chain described above.
- Without L6: 521 tokens; removes `const maze = rows.join("").split("");` from the dependency chain described above.
- Without L7: 510 tokens; removes `const start = maze.indexOf("S"), goal = maze.indexOf("G");` from the dependency chain described above.
- Without L8: 513 tokens; removes `const parent = Array(maze.length).fill(-1), queue = [start];` from the dependency chain described above.
- Without L9: 532 tokens; removes `parent[start] = start;` from the dependency chain described above.
- Without L10: 515 tokens; removes `for (let head = 0; head < queue.length; head++) {` from the dependency chain described above.
- Without L11: 529 tokens; removes `const cell = queue[head];` from the dependency chain described above.
- Without L12: 528 tokens; removes `if (cell === goal) break;` from the dependency chain described above.
- Without L13: 512 tokens; removes `const row = Math.floor(cell / width), column = cell % width;` from the dependency chain described above.
- Without L14: 491 tokens; removes `for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {` from the dependency chain described above.
- Without L15: 517 tokens; removes `const r = row + dr, c = column + dc;` from the dependency chain described above.
- Without L16: 505 tokens; removes `if (r >= 0 && r < height && c >= 0 && c < width) {` from the dependency chain described above.
- Without L17: 523 tokens; removes `const neighbor = r * width + c;` from the dependency chain described above.
- Without L18: 512 tokens; removes `if (maze[neighbor] !== "#" && parent[neighbor] < 0) {` from the dependency chain described above.
- Without L19: 530 tokens; removes `parent[neighbor] = cell;` from the dependency chain described above.
- Without L20: 532 tokens; removes `queue.push(neighbor);` from the dependency chain described above.
- Without L21: 538 tokens; removes `}` from the dependency chain described above.
- Without L22: 539 tokens; removes `}` from the dependency chain described above.
- Without L23: 539 tokens; removes `}` from the dependency chain described above.
- Without L24: 540 tokens; removes `}` from the dependency chain described above.
- Without L25: 533 tokens; removes `let steps = 0;` from the dependency chain described above.
- Without L26: 511 tokens; removes `for (let cell = goal; cell !== start; cell = parent[cell]) {` from the dependency chain described above.
- Without L27: 537 tokens; removes `steps++;` from the dependency chain described above.
- Without L28: 514 tokens; removes `if (maze[cell] === ".") maze[cell] = "*";` from the dependency chain described above.
- Without L29: 540 tokens; removes `}` from the dependency chain described above.
- Without L30: 526 tokens; removes `console.log(`steps: ${steps}`);` from the dependency chain described above.
- Without L31: 512 tokens; removes `for (let offset = 0; offset < maze.length; offset += width) {` from the dependency chain described above.
- Without L32: 515 tokens; removes `console.log(maze.slice(offset, offset + width).join(""));` from the dependency chain described above.
