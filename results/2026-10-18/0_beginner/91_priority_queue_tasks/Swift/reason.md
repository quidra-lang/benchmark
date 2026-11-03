# Task B selection: 91_priority_queue_tasks / Swift

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

## Answer and source dependencies

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.



## Scope and dependency evidence checked after independent review

Connect the custom comparison to the actual queue type/instance and both run and remaining removals. Keep the primary-priority branch separate from its name tie-break. These declaration/boundary links establish shared comparator use rather than relying on an unbound operator/method name.

Source: `main.swift`. Selected original locations: L1,L2,L6,L7,L8,L9,L11,L12,L14,L19,L25,L32,L33,L44,L51,L55.

- L1: `struct Task {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    let name: String` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    func precedes(_ other: Task) -> Bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        priority == other.priority ? sequence < other.sequence : priority < other.priority` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `struct Heap {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    var tasks = [Task]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    mutating func push(_ task: Task) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            if !tasks[i].precedes(tasks[parent]) { break }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    mutating func pop() -> Task {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            if child + 1 < tasks.count && tasks[child + 1].precedes(tasks[child]) { child += 1 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            if !tasks[child].precedes(tasks[i]) { break }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `var queue = Heap(), sequence = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        let task = queue.pop()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `let remaining = queue.tasks.sorted { $0.precedes($1) }.map { $0.name }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **279 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 232 tokens. The contiguous original span L1–L55 costs 792 tokens; the complete original source costs 815 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 273 tokens; removes `struct Task {` from the dependency chain described above.
- Without L2: 271 tokens; removes `let name: String` from the dependency chain described above.
- Without L6: 260 tokens; removes `func precedes(_ other: Task) -> Bool {` from the dependency chain described above.
- Without L7: 249 tokens; removes `priority == other.priority ? sequence < other.sequence : priority < other.priority` from the dependency chain described above.
- Without L8: 276 tokens; removes `}` from the dependency chain described above.
- Without L9: 277 tokens; removes `}` from the dependency chain described above.
- Without L11: 273 tokens; removes `struct Heap {` from the dependency chain described above.
- Without L12: 266 tokens; removes `var tasks = [Task]()` from the dependency chain described above.
- Without L14: 262 tokens; removes `mutating func push(_ task: Task) {` from the dependency chain described above.
- Without L19: 255 tokens; removes `if !tasks[i].precedes(tasks[parent]) { break }` from the dependency chain described above.
- Without L25: 264 tokens; removes `mutating func pop() -> Task {` from the dependency chain described above.
- Without L32: 234 tokens; removes `if child + 1 < tasks.count && tasks[child + 1].precedes(tasks[child]) { child += 1 }` from the dependency chain described above.
- Without L33: 255 tokens; removes `if !tasks[child].precedes(tasks[i]) { break }` from the dependency chain described above.
- Without L44: 262 tokens; removes `var queue = Heap(), sequence = 0` from the dependency chain described above.
- Without L51: 265 tokens; removes `let task = queue.pop()` from the dependency chain described above.
- Without L55: 243 tokens; removes `let remaining = queue.tasks.sorted { $0.precedes($1) }.map { $0.name }` from the dependency chain described above.
