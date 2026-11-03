# Task B selection: 88_maze_shortest_path / Go

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.go`. Selected original locations: L9,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49.

- L9: `	parent, distance := [117]int{}, [117]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `	for i := 0; i < 117; i++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `		parent[i] = -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `		if maze[i/13][i%13] == 'S' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `			start = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `		if maze[i/13][i%13] == 'G' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `			goal = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `	queue := []int{start}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `	parent[start] = start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `	directions := [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `	for head := 0; head < len(queue); head++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `		v := queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `		r, c := v/13, v%13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `		for _, d := range directions {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `			rr, cc := r+d[0], c+d[1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `			if rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `				continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `			}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `			w := rr*13 + cc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `			if parent[w] < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `				parent[w] = v` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `				distance[w] = distance[v] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `				queue = append(queue, w)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `			}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `	for v := goal; v != start; v = parent[v] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `		if maze[v/13][v%13] == '.' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `			maze[v/13][v%13] = '*'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `	fmt.Printf("steps: %d\n", distance[goal])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `	for _, row := range maze {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `		fmt.Println(string(row))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **600 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 391 tokens. The contiguous original span L9–L49 costs 647 tokens; the complete original source costs 796 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L9: 573 tokens; removes `parent, distance := [117]int{}, [117]int{}` from the dependency chain described above.
- Without L14: 576 tokens; removes `for i := 0; i < 117; i++ {` from the dependency chain described above.
- Without L15: 588 tokens; removes `parent[i] = -1` from the dependency chain described above.
- Without L16: 574 tokens; removes `if maze[i/13][i%13] == 'S' {` from the dependency chain described above.
- Without L17: 591 tokens; removes `start = i` from the dependency chain described above.
- Without L18: 596 tokens; removes `}` from the dependency chain described above.
- Without L19: 574 tokens; removes `if maze[i/13][i%13] == 'G' {` from the dependency chain described above.
- Without L20: 591 tokens; removes `goal = i` from the dependency chain described above.
- Without L21: 596 tokens; removes `}` from the dependency chain described above.
- Without L22: 597 tokens; removes `}` from the dependency chain described above.
- Without L23: 589 tokens; removes `queue := []int{start}` from the dependency chain described above.
- Without L24: 590 tokens; removes `parent[start] = start` from the dependency chain described above.
- Without L25: 555 tokens; removes `directions := [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}` from the dependency chain described above.
- Without L26: 575 tokens; removes `for head := 0; head < len(queue); head++ {` from the dependency chain described above.
- Without L27: 589 tokens; removes `v := queue[head]` from the dependency chain described above.
- Without L28: 580 tokens; removes `r, c := v/13, v%13` from the dependency chain described above.
- Without L29: 583 tokens; removes `for _, d := range directions {` from the dependency chain described above.
- Without L30: 575 tokens; removes `rr, cc := r+d[0], c+d[1]` from the dependency chain described above.
- Without L31: 546 tokens; removes `if rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#' {` from the dependency chain described above.
- Without L32: 594 tokens; removes `continue` from the dependency chain described above.
- Without L33: 595 tokens; removes `}` from the dependency chain described above.
- Without L34: 584 tokens; removes `w := rr*13 + cc` from the dependency chain described above.
- Without L35: 584 tokens; removes `if parent[w] < 0 {` from the dependency chain described above.
- Without L36: 587 tokens; removes `parent[w] = v` from the dependency chain described above.
- Without L37: 580 tokens; removes `distance[w] = distance[v] + 1` from the dependency chain described above.
- Without L38: 584 tokens; removes `queue = append(queue, w)` from the dependency chain described above.
- Without L39: 595 tokens; removes `}` from the dependency chain described above.
- Without L40: 596 tokens; removes `}` from the dependency chain described above.
- Without L41: 597 tokens; removes `}` from the dependency chain described above.
- Without L42: 572 tokens; removes `for v := goal; v != start; v = parent[v] {` from the dependency chain described above.
- Without L43: 574 tokens; removes `if maze[v/13][v%13] == '.' {` from the dependency chain described above.
- Without L44: 577 tokens; removes `maze[v/13][v%13] = '*'` from the dependency chain described above.
- Without L45: 596 tokens; removes `}` from the dependency chain described above.
- Without L46: 597 tokens; removes `}` from the dependency chain described above.
- Without L47: 578 tokens; removes `fmt.Printf("steps: %d\n", distance[goal])` from the dependency chain described above.
- Without L48: 584 tokens; removes `for _, row := range maze {` from the dependency chain described above.
- Without L49: 588 tokens; removes `fmt.Println(string(row))` from the dependency chain described above.
