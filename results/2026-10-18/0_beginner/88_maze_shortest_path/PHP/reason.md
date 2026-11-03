# Task B selection: 88_maze_shortest_path / PHP

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.php`. Selected original locations: L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57.

- L16: `foreach ($maze as $row => $values) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    foreach ($values as $column => $c) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        if ($c === 'S') {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            $start = [$row, $column];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `        if ($c === 'G') {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            $goal = [$row, $column];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `$key = fn($cell) => $cell[0] . ',' . $cell[1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `$queue = [$start];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `$parents = [$key($start) => $start];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `$head = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `while ($head < count($queue)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    $cell = $queue[$head++];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    if ($cell === $goal) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        $r = $cell[0] + $dr;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        $c = $cell[1] + $dc;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        $next = [$r, $c];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        if ($r >= 0 && $r < 9 && $c >= 0 && $c < 13 && $maze[$r][$c] !== '#' && !isset($parents[$key($next)])) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            $parents[$key($next)] = $cell;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `            $queue[] = $next;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `$cell = $goal;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `$steps = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `while ($cell !== $start) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    [$r, $c] = $cell;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    if ($maze[$r][$c] === '.') {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        $maze[$r][$c] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `    $cell = $parents[$key($cell)];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    $steps++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L55: `printf("steps: %d\n", $steps);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `foreach ($maze as $row) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    echo implode('', $row), "\n";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **649 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 491 tokens. The contiguous original span L16–L57 costs 649 tokens; the complete original source costs 808 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L16: 630 tokens; removes `foreach ($maze as $row => $values) {` from the dependency chain described above.
- Without L17: 629 tokens; removes `foreach ($values as $column => $c) {` from the dependency chain described above.
- Without L18: 632 tokens; removes `if ($c === 'S') {` from the dependency chain described above.
- Without L19: 631 tokens; removes `$start = [$row, $column];` from the dependency chain described above.
- Without L20: 645 tokens; removes `}` from the dependency chain described above.
- Without L21: 632 tokens; removes `if ($c === 'G') {` from the dependency chain described above.
- Without L22: 631 tokens; removes `$goal = [$row, $column];` from the dependency chain described above.
- Without L23: 645 tokens; removes `}` from the dependency chain described above.
- Without L24: 646 tokens; removes `}` from the dependency chain described above.
- Without L25: 647 tokens; removes `}` from the dependency chain described above.
- Without L26: 615 tokens; removes `$key = fn($cell) => $cell[0] . ',' . $cell[1];` from the dependency chain described above.
- Without L27: 638 tokens; removes `$queue = [$start];` from the dependency chain described above.
- Without L28: 629 tokens; removes `$parents = [$key($start) => $start];` from the dependency chain described above.
- Without L29: 641 tokens; removes `$head = 0;` from the dependency chain described above.
- Without L30: 632 tokens; removes `while ($head < count($queue)) {` from the dependency chain described above.
- Without L31: 634 tokens; removes `$cell = $queue[$head++];` from the dependency chain described above.
- Without L32: 634 tokens; removes `if ($cell === $goal) {` from the dependency chain described above.
- Without L33: 644 tokens; removes `break;` from the dependency chain described above.
- Without L34: 646 tokens; removes `}` from the dependency chain described above.
- Without L35: 598 tokens; removes `foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {` from the dependency chain described above.
- Without L36: 630 tokens; removes `$r = $cell[0] + $dr;` from the dependency chain described above.
- Without L37: 630 tokens; removes `$c = $cell[1] + $dc;` from the dependency chain described above.
- Without L38: 632 tokens; removes `$next = [$r, $c];` from the dependency chain described above.
- Without L39: 570 tokens; removes `if ($r >= 0 && $r < 9 && $c >= 0 && $c < 13 && $maze[$r][$c] !== '#' && !isset($parents[$key($next)])) {` from the dependency chain described above.
- Without L40: 629 tokens; removes `$parents[$key($next)] = $cell;` from the dependency chain described above.
- Without L41: 636 tokens; removes `$queue[] = $next;` from the dependency chain described above.
- Without L42: 645 tokens; removes `}` from the dependency chain described above.
- Without L43: 646 tokens; removes `}` from the dependency chain described above.
- Without L44: 647 tokens; removes `}` from the dependency chain described above.
- Without L45: 640 tokens; removes `$cell = $goal;` from the dependency chain described above.
- Without L46: 641 tokens; removes `$steps = 0;` from the dependency chain described above.
- Without L47: 635 tokens; removes `while ($cell !== $start) {` from the dependency chain described above.
- Without L48: 633 tokens; removes `[$r, $c] = $cell;` from the dependency chain described above.
- Without L49: 625 tokens; removes `if ($maze[$r][$c] === '.') {` from the dependency chain described above.
- Without L50: 629 tokens; removes `$maze[$r][$c] = '*';` from the dependency chain described above.
- Without L51: 646 tokens; removes `}` from the dependency chain described above.
- Without L52: 631 tokens; removes `$cell = $parents[$key($cell)];` from the dependency chain described above.
- Without L53: 643 tokens; removes `$steps++;` from the dependency chain described above.
- Without L54: 647 tokens; removes `}` from the dependency chain described above.
- Without L55: 631 tokens; removes `printf("steps: %d\n", $steps);` from the dependency chain described above.
- Without L56: 635 tokens; removes `foreach ($maze as $row) {` from the dependency chain described above.
- Without L57: 629 tokens; removes `echo implode('', $row), "\n";` from the dependency chain described above.
