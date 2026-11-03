# Task B source selection

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.

SplPriorityQueue is a max-heap. Retain reversed numeric priority and use a custom comparison for names that makes the alphabetically smaller name rank higher; simply inserting the name as the second maximum key would give the wrong order.

## Source evidence and dependencies

The selected locations in `main.php` are L8, L12, L14, L20. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L8: `$queue = new SplPriorityQueue();`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L12: `$queue->insert([$parts[1], (int) $parts[2]], [-(int) $parts[2], -$sequence]);`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L14: `[$name, $priority] = $queue->extract();`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.
- L20: `$remaining[] = $queue->extract()[0];`. This line supplies the priority/sequence comparison, tuple/name layout, comparator call or run/remaining consumer. These identify the exact comparison edit and every affected name-access or comparator dependency.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **99 tokens** for the selected original complete lines. A contiguous-context alternative spanning L8–L20 costs **221 tokens**; the entire source costs **388 tokens**. The selected set plus the additional context line L1 costs **103 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
