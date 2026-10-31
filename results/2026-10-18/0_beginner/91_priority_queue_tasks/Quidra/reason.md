# Task B source selection

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.

before currently receives only priorities, so add names to before and thread that parameter through push, pop and their shown call sites. Equal-priority IDs must compare names[a] and names[b].

## Source evidence and dependencies

The selected locations in `main.qui` are L1, L2, L4, L9, L14, L24, L26, L43, L44, L45, L46, L47, L49, L53, L54. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `bool before(int a, int b, int[] priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L2: `return priorities[a] < priorities[b] or (priorities[a] == priorities[b] and a < b)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L4: `void push(int value, int[] &heap, int[] priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L9: `if not before(heap[index], heap[parent], priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L14: `int pop(int[] &heap, int[] priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L24: `if child + 1 < int(len(heap)) and before(heap[child + 1], heap[child], priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L26: `if not before(heap[child], heap[index], priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L43: `int id = int(len(names))`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L44: `names = names.append(fields[1])`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L45: `int priority = int.parse(fields[2])`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L46: `priorities = priorities.append(priority)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L47: `push(id, &heap, priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L49: `int id = pop(&heap, priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L53: `int id = pop(&heap, priorities)`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L54: `remaining = remaining.append(names[id])`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **312 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L54 costs **859 tokens**; the entire source costs **881 tokens**. The selected set plus the additional context line L5 costs **324 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
