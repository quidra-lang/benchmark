# Task B: 91_priority_queue_tasks / Julia

Use (priority,ascending task name) for every heap comparison instead of (priority,insertion sequence), including both sift directions and the final repeated removals. The revised run lines are `run: deploy (priority 1)`, `run: test (priority 2)`, `run: email (priority 3)`, `run: review (priority 2)`, `run: build (priority 1)`, `run: lint (priority 3)`. Final output is `remaining: report docs backup cleanup`. Parse priorities as numbers and retain names as text; the remaining list must be drained under the same comparator, not sorted by the old insertion rule.

The tuple currently orders (priority,sequence,name) under isless. Store/order (priority,name,sequence) and adjust pop destructuring/indexing so heap_push!, heap_pop! and remaining extraction all agree.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64.

- L1: `function heap_push!(heap, task)`
- L2: `push!(heap, task)`
- L3: `child = length(heap)`
- L4: `while child > 1`
- L5: `parent = div(child, 2)`
- L6: `!isless(heap[child], heap[parent]) && break`
- L7: `heap[child], heap[parent] = heap[parent], heap[child]`
- L8: `child = parent`
- L9: `end`
- L10: `end`
- L12: `function heap_pop!(heap)`
- L13: `task = heap[1]`
- L14: `last = pop!(heap)`
- L15: `if !isempty(heap)`
- L16: `heap[1] = last`
- L17: `parent = 1`
- L18: `while 2*parent <= length(heap)`
- L19: `child = 2*parent`
- L20: `if child < length(heap) && isless(heap[child+1], heap[child])`
- L21: `child += 1`
- L22: `end`
- L23: `!isless(heap[child], heap[parent]) && break`
- L24: `heap[child], heap[parent] = heap[parent], heap[child]`
- L25: `parent = child`
- L26: `end`
- L27: `end`
- L28: `return task`
- L29: `end`
- L32: `operations = [`
- L33: `"add email 3",`
- L34: `"add backup 5",`
- L35: `"add deploy 1",`
- L36: `"run",`
- L37: `"add report 3",`
- L38: `"add test 2",`
- L39: `"add lint 3",`
- L40: `"run",`
- L41: `"run",`
- L42: `"add cleanup 5",`
- L43: `"add review 2",`
- L44: `"run",`
- L45: `"add build 1",`
- L46: `"add docs 4",`
- L47: `"run",`
- L48: `"run",`
- L49: `]`
- L50: `heap = Tuple{Int,Int,String}[]`
- L51: `for (sequence, operation) in enumerate(operations)`
- L52: `parts = split(operation)`
- L53: `if parts[1] == "add"`
- L54: `heap_push!(heap, (parse(Int, parts[3]), sequence, String(parts[2])))`
- L55: `else`
- L56: `priority, _, name = heap_pop!(heap)`
- L57: `println("run: ", name, " (priority ", priority, ")")`
- L58: `end`
- L59: `end`
- L60: `remaining = String[]`
- L61: `while !isempty(heap)`
- L62: `push!(remaining, heap_pop!(heap)[3])`
- L63: `end`
- L64: `println("remaining: ", join(remaining, " "))`

Minimization: The comparator, both custom heap helpers, sixteen operations, parser/entry representation, run output and final drain are needed. This end-to-end dependency covers the substantive program without relying on a generic full-source fallback. The selected complete original lines, in source order, cost 701 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 708, and the complete source costs 714. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
