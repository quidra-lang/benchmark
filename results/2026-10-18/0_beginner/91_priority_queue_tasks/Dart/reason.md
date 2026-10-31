# Task B selection: 91_priority_queue_tasks / Dart

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

## Answer and source dependencies

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.



## Scope and dependency evidence checked after independent review

The named task/heap declarations associate the selected name field and comparator-bearing methods with the actual queue receiver. This closes the static call/type dependency from both removals to the edited name tie-break, without relying on an unrelated operator/method signature.

Source: `main.dart`. Selected original locations: L1,L2,L5,L7,L8,L9,L11,L12,L13,L18,L24,L26,L34,L37,L45,L46,L67,L74,L80.

- L1: `class Task {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  final String name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `bool before(Task a, Task b) => a.priority != b.priority` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    ? a.priority < b.priority` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    : a.sequence < b.sequence;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `class Heap {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  final items = <Task>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  void push(Task task) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      if (!before(items[i], items[p])) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `  Task pop() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            before(items[child + 1], items[child])) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        if (!before(items[child], items[i])) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L67: `  final heap = Heap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `      final task = heap.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `    remaining.add(heap.pop().name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **231 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 215 tokens. The contiguous original span L1–L80 costs 887 tokens; the complete original source costs 914 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 225 tokens; removes `class Task {` from the dependency chain described above.
- Without L2: 223 tokens; removes `final String name;` from the dependency chain described above.
- Without L5: 229 tokens; removes `}` from the dependency chain described above.
- Without L7: 205 tokens; removes `bool before(Task a, Task b) => a.priority != b.priority` from the dependency chain described above.
- Without L8: 218 tokens; removes `? a.priority < b.priority` from the dependency chain described above.
- Without L9: 217 tokens; removes `: a.sequence < b.sequence;` from the dependency chain described above.
- Without L11: 225 tokens; removes `class Heap {` from the dependency chain described above.
- Without L12: 218 tokens; removes `final items = <Task>[];` from the dependency chain described above.
- Without L13: 219 tokens; removes `void push(Task task) {` from the dependency chain described above.
- Without L18: 207 tokens; removes `if (!before(items[i], items[p])) break;` from the dependency chain described above.
- Without L24: 228 tokens; removes `}` from the dependency chain described above.
- Without L26: 222 tokens; removes `Task pop() {` from the dependency chain described above.
- Without L34: 207 tokens; removes `before(items[child + 1], items[child])) {` from the dependency chain described above.
- Without L37: 207 tokens; removes `if (!before(items[child], items[i])) break;` from the dependency chain described above.
- Without L45: 228 tokens; removes `}` from the dependency chain described above.
- Without L46: 229 tokens; removes `}` from the dependency chain described above.
- Without L67: 219 tokens; removes `final heap = Heap();` from the dependency chain described above.
- Without L74: 216 tokens; removes `final task = heap.pop();` from the dependency chain described above.
- Without L80: 216 tokens; removes `remaining.add(heap.pop().name);` from the dependency chain described above.
