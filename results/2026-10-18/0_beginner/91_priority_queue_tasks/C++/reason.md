# Task B selection: 91_priority_queue_tasks / C++

## Common answer requirements

Identify priority/sequence tie comparison and both run and final-remaining dependencies; specify ascending name tie-break with smaller priority first and unchanged formats.

## Answer and source dependencies

Replace only the secondary insertion-order comparison with ascending task-name comparison, preserving numeric priority as the primary key. A shared heap comparator automatically governs repeated removals; a separately sorted remaining view must use that same comparator. Tuple-based heaps can change their ordering key to (priority,name,...) but must adjust destructuring and positional name extraction to match. Max-heaps need the comparator/key orientation that still makes smaller priorities and alphabetically earlier names run first. Where comparisons use numeric IDs, make the names array available to the comparator and update affected signatures/calls rather than treating IDs as alphabetical order.



## Scope and dependency evidence checked after independent review

The named task/heap declarations associate the selected name field and comparator-bearing methods with the actual queue receiver. This closes the static call/type dependency from both removals to the edited name tie-break, without relying on an unrelated operator/method signature.

Source: `main.cpp`. Selected original locations: L8,L9,L11,L13,L14,L15,L16,L17,L20,L27,L28,L41,L42.

- L8: `struct Task {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    std::string name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `struct Later {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    bool operator()(const Task &a, const Task &b) const {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        return a.priority != b.priority ? a.priority > b.priority : a.order > b.order;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `    std::priority_queue<Task, std::vector<Task>, Later> queue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            Task task = queue.top();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            queue.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        std::cout << ' ' << queue.top().name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        queue.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **177 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 168 tokens. The contiguous original span L8–L42 costs 552 tokens; the complete original source costs 613 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 171 tokens; removes `struct Task {` from the dependency chain described above.
- Without L9: 169 tokens; removes `std::string name;` from the dependency chain described above.
- Without L11: 174 tokens; removes `};` from the dependency chain described above.
- Without L13: 171 tokens; removes `struct Later {` from the dependency chain described above.
- Without L14: 150 tokens; removes `bool operator()(const Task &a, const Task &b) const {` from the dependency chain described above.
- Without L15: 138 tokens; removes `return a.priority != b.priority ? a.priority > b.priority : a.order > b.order;` from the dependency chain described above.
- Without L16: 174 tokens; removes `}` from the dependency chain described above.
- Without L17: 174 tokens; removes `};` from the dependency chain described above.
- Without L20: 153 tokens; removes `std::priority_queue<Task, std::vector<Task>, Later> queue;` from the dependency chain described above.
- Without L27: 161 tokens; removes `Task task = queue.top();` from the dependency chain described above.
- Without L28: 167 tokens; removes `queue.pop();` from the dependency chain described above.
- Without L41: 154 tokens; removes `std::cout << ' ' << queue.top().name;` from the dependency chain described above.
- Without L42: 168 tokens; removes `queue.pop();` from the dependency chain described above.
