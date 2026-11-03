# Task B selection: 88_maze_shortest_path / Zig

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.zig`. Selected original locations: L5,L6,L21,L22,L23,L24,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58.

- L5: `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    const out = &writer.interface;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    const start = std.mem.findScalar(u8, &maze, 'S').?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    const goal = std.mem.findScalar(u8, &maze, 'G').?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    var parent: [117]i32 = @splat(-1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    parent[start] = @intCast(start);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    queue[0] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    var head: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    var tail: usize = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    const directions = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    while (head < tail) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        const v = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        head += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        if (v == goal)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        for (directions) |d| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            const r = @as(i32, @intCast(v / 13)) + d[0];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            const c = @as(i32, @intCast(v % 13)) + d[1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            if (r < 0 or r >= 9 or c < 0 or c >= 13)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `                continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            const u: usize = @intCast(r * 13 + c);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `            if (maze[u] != '#' and parent[u] == -1) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `                parent[u] = @intCast(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                queue[tail] = u;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `                tail += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `    var current = goal;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    var steps: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    while (current != start) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        if (current != goal)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `            maze[current] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        current = @intCast(parent[current]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        steps += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L56: `    try out.print("steps: {d}\n", .{steps});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    for (0..9) |r|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        try out.print("{s}\n", .{maze[r * 13 .. r * 13 + 13]});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **719 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 436 tokens. The contiguous original span L5–L58 costs 938 tokens; the complete original source costs 1008 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 687 tokens; removes `var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` from the dependency chain described above.
- Without L6: 706 tokens; removes `const out = &writer.interface;` from the dependency chain described above.
- Without L21: 691 tokens; removes `const start = std.mem.findScalar(u8, &maze, 'S').?;` from the dependency chain described above.
- Without L22: 691 tokens; removes `const goal = std.mem.findScalar(u8, &maze, 'G').?;` from the dependency chain described above.
- Without L23: 696 tokens; removes `var parent: [117]i32 = @splat(-1);` from the dependency chain described above.
- Without L24: 703 tokens; removes `parent[start] = @intCast(start);` from the dependency chain described above.
- Without L26: 708 tokens; removes `queue[0] = start;` from the dependency chain described above.
- Without L27: 706 tokens; removes `var head: usize = 0;` from the dependency chain described above.
- Without L28: 706 tokens; removes `var tail: usize = 1;` from the dependency chain described above.
- Without L29: 655 tokens; removes `const directions = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };` from the dependency chain described above.
- Without L30: 706 tokens; removes `while (head < tail) {` from the dependency chain described above.
- Without L31: 705 tokens; removes `const v = queue[head];` from the dependency chain described above.
- Without L32: 710 tokens; removes `head += 1;` from the dependency chain described above.
- Without L33: 707 tokens; removes `if (v == goal)` from the dependency chain described above.
- Without L34: 713 tokens; removes `break;` from the dependency chain described above.
- Without L35: 705 tokens; removes `for (directions) |d| {` from the dependency chain described above.
- Without L36: 683 tokens; removes `const r = @as(i32, @intCast(v / 13)) + d[0];` from the dependency chain described above.
- Without L37: 683 tokens; removes `const c = @as(i32, @intCast(v % 13)) + d[1];` from the dependency chain described above.
- Without L38: 681 tokens; removes `if (r < 0 or r >= 9 or c < 0 or c >= 13)` from the dependency chain described above.
- Without L39: 712 tokens; removes `continue;` from the dependency chain described above.
- Without L40: 691 tokens; removes `const u: usize = @intCast(r * 13 + c);` from the dependency chain described above.
- Without L41: 687 tokens; removes `if (maze[u] != '#' and parent[u] == -1) {` from the dependency chain described above.
- Without L42: 700 tokens; removes `parent[u] = @intCast(v);` from the dependency chain described above.
- Without L43: 705 tokens; removes `queue[tail] = u;` from the dependency chain described above.
- Without L44: 708 tokens; removes `tail += 1;` from the dependency chain described above.
- Without L45: 714 tokens; removes `}` from the dependency chain described above.
- Without L46: 715 tokens; removes `}` from the dependency chain described above.
- Without L47: 716 tokens; removes `}` from the dependency chain described above.
- Without L48: 709 tokens; removes `var current = goal;` from the dependency chain described above.
- Without L49: 706 tokens; removes `var steps: usize = 0;` from the dependency chain described above.
- Without L50: 706 tokens; removes `while (current != start) {` from the dependency chain described above.
- Without L51: 707 tokens; removes `if (current != goal)` from the dependency chain described above.
- Without L52: 704 tokens; removes `maze[current] = '*';` from the dependency chain described above.
- Without L53: 702 tokens; removes `current = @intCast(parent[current]);` from the dependency chain described above.
- Without L54: 710 tokens; removes `steps += 1;` from the dependency chain described above.
- Without L55: 716 tokens; removes `}` from the dependency chain described above.
- Without L56: 693 tokens; removes `try out.print("steps: {d}\n", .{steps});` from the dependency chain described above.
- Without L57: 706 tokens; removes `for (0..9) |r|` from the dependency chain described above.
- Without L58: 673 tokens; removes `try out.print("{s}\n", .{maze[r * 13 .. r * 13 + 13]});` from the dependency chain described above.
