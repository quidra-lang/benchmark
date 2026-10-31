# Task B source selection

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.



## Source evidence and dependencies

The selected locations in `main.zig` are L3, L5, L6, L7, L8, L9, L34, L46, L51, L52. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L3: `const Task = struct { name: []const u8, priority: u32, sequence: usize };`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L5: `fn compare(_: void, a: Task, b: Task) std.math.Order {`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L6: `return if (a.priority != b.priority)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L7: `std.math.order(a.priority, b.priority)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L8: `else`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L9: `std.math.order(a.sequence, b.sequence);`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L34: `var heap: std.PriorityQueue(Task, void, compare) = .empty;`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L46: `const task = heap.pop().?;`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L51: `while (heap.pop()) |task| {`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L52: `try out.print(" {s}", .{task.name});`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **203 tokens** for the selected original complete lines. A contiguous-context alternative spanning L3–L52 costs **761 tokens**; the entire source costs **807 tokens**. The selected set plus the additional context line L1 costs **218 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
