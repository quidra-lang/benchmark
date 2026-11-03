# Task B selection: 91_priority_queue_tasks / Go

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

## Answer and source dependencies

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.



## Scope and dependency evidence checked after independent review

The named task/heap declarations associate the selected name field and comparator-bearing methods with the actual queue receiver. This closes the static call/type dependency from both removals to the edited name tie-break, without relying on an unrelated operator/method signature.

Source: `main.go`. Selected original locations: L8,L9,L11,L13,L17,L18,L19,L20,L21,L37,L44,L55.

- L8: `type Task struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `	name            string` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `type TaskQueue []Task` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `func (q TaskQueue) Less(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `	if q[i].priority != q[j].priority {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `		return q[i].priority < q[j].priority` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `	return q[i].order < q[j].order` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `	queue := TaskQueue{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `			task := heap.Pop(&queue).(Task)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `		task := heap.Pop(&queue).(Task)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **155 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 145 tokens. The contiguous original span L8–L55 costs 669 tokens; the complete original source costs 723 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 147 tokens; removes `type Task struct {` from the dependency chain described above.
- Without L9: 145 tokens; removes `name            string` from the dependency chain described above.
- Without L11: 153 tokens; removes `}` from the dependency chain described above.
- Without L13: 147 tokens; removes `type TaskQueue []Task` from the dependency chain described above.
- Without L17: 132 tokens; removes `func (q TaskQueue) Less(i, j int) bool {` from the dependency chain described above.
- Without L18: 136 tokens; removes `if q[i].priority != q[j].priority {` from the dependency chain described above.
- Without L19: 137 tokens; removes `return q[i].priority < q[j].priority` from the dependency chain described above.
- Without L20: 152 tokens; removes `}` from the dependency chain described above.
- Without L21: 138 tokens; removes `return q[i].order < q[j].order` from the dependency chain described above.
- Without L37: 145 tokens; removes `queue := TaskQueue{}` from the dependency chain described above.
- Without L44: 136 tokens; removes `task := heap.Pop(&queue).(Task)` from the dependency chain described above.
- Without L55: 137 tokens; removes `task := heap.Pop(&queue).(Task)` from the dependency chain described above.
