# Task B selection: 88_maze_shortest_path / Rust

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.rs`. Selected original locations: L16,L17,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56.

- L16: `    let mut parent = [None; 117];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    let mut distance = [0; 117];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    for i in 0..117 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        if maze[i / 13][i % 13] == b'S' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            start = i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `        if maze[i / 13][i % 13] == b'G' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            goal = i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    let mut queue = std::collections::VecDeque::from([start]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    parent[start] = Some(start);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    while let Some(v) = queue.pop_front() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        let (r, c) = ((v / 13) as i32, (v % 13) as i32);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            let (rr, cc) = (r + dr, c + dc);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            if !(0..9).contains(&rr)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `                || !(0..13).contains(&cc)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `                || maze[rr as usize][cc as usize] == b'#'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `                continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `            let w = rr as usize * 13 + cc as usize;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            if parent[w].is_none() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                parent[w] = Some(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `                distance[w] = distance[v] + 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                queue.push_back(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `    let mut v = goal;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    while v != start {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        if maze[v / 13][v % 13] == b'.' {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `            maze[v / 13][v % 13] = b'*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `        v = parent[v].unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L54: `    println!("steps: {}", distance[goal]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    for row in maze {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        println!("{}", String::from_utf8(row).unwrap());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **685 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 462 tokens. The contiguous original span L16–L56 costs 709 tokens; the complete original source costs 897 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L16: 666 tokens; removes `let mut parent = [None; 117];` from the dependency chain described above.
- Without L17: 666 tokens; removes `let mut distance = [0; 117];` from the dependency chain described above.
- Without L19: 670 tokens; removes `for i in 0..117 {` from the dependency chain described above.
- Without L20: 654 tokens; removes `if maze[i / 13][i % 13] == b'S' {` from the dependency chain described above.
- Without L21: 675 tokens; removes `start = i;` from the dependency chain described above.
- Without L22: 681 tokens; removes `}` from the dependency chain described above.
- Without L23: 654 tokens; removes `if maze[i / 13][i % 13] == b'G' {` from the dependency chain described above.
- Without L24: 675 tokens; removes `goal = i;` from the dependency chain described above.
- Without L25: 681 tokens; removes `}` from the dependency chain described above.
- Without L26: 682 tokens; removes `}` from the dependency chain described above.
- Without L27: 661 tokens; removes `let mut queue = std::collections::VecDeque::from([start]);` from the dependency chain described above.
- Without L28: 671 tokens; removes `parent[start] = Some(start);` from the dependency chain described above.
- Without L29: 663 tokens; removes `while let Some(v) = queue.pop_front() {` from the dependency chain described above.
- Without L30: 642 tokens; removes `let (r, c) = ((v / 13) as i32, (v % 13) as i32);` from the dependency chain described above.
- Without L31: 635 tokens; removes `for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {` from the dependency chain described above.
- Without L32: 655 tokens; removes `let (rr, cc) = (r + dr, c + dc);` from the dependency chain described above.
- Without L33: 667 tokens; removes `if !(0..9).contains(&rr)` from the dependency chain described above.
- Without L34: 665 tokens; removes `|| !(0..13).contains(&cc)` from the dependency chain described above.
- Without L35: 656 tokens; removes `|| maze[rr as usize][cc as usize] == b'#'` from the dependency chain described above.
- Without L36: 680 tokens; removes `{` from the dependency chain described above.
- Without L37: 678 tokens; removes `continue;` from the dependency chain described above.
- Without L38: 680 tokens; removes `}` from the dependency chain described above.
- Without L39: 656 tokens; removes `let w = rr as usize * 13 + cc as usize;` from the dependency chain described above.
- Without L40: 668 tokens; removes `if parent[w].is_none() {` from the dependency chain described above.
- Without L41: 668 tokens; removes `parent[w] = Some(v);` from the dependency chain described above.
- Without L42: 664 tokens; removes `distance[w] = distance[v] + 1;` from the dependency chain described above.
- Without L43: 671 tokens; removes `queue.push_back(w);` from the dependency chain described above.
- Without L44: 680 tokens; removes `}` from the dependency chain described above.
- Without L45: 681 tokens; removes `}` from the dependency chain described above.
- Without L46: 682 tokens; removes `}` from the dependency chain described above.
- Without L47: 673 tokens; removes `let mut v = goal;` from the dependency chain described above.
- Without L48: 674 tokens; removes `while v != start {` from the dependency chain described above.
- Without L49: 654 tokens; removes `if maze[v / 13][v % 13] == b'.' {` from the dependency chain described above.
- Without L50: 656 tokens; removes `maze[v / 13][v % 13] = b'*';` from the dependency chain described above.
- Without L51: 681 tokens; removes `}` from the dependency chain described above.
- Without L52: 670 tokens; removes `v = parent[v].unwrap();` from the dependency chain described above.
- Without L53: 682 tokens; removes `}` from the dependency chain described above.
- Without L54: 665 tokens; removes `println!("steps: {}", distance[goal]);` from the dependency chain described above.
- Without L55: 674 tokens; removes `for row in maze {` from the dependency chain described above.
- Without L56: 659 tokens; removes `println!("{}", String::from_utf8(row).unwrap());` from the dependency chain described above.
