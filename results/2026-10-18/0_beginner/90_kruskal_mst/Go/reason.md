# Task B selection: 90_kruskal_mst / Go

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.go`. Selected original locations: L13,L14,L15,L16,L17,L18,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42.

- L13: `func find(parent *[8]int, v int) int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `	if parent[v] != v {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `		parent[v] = find(parent, parent[v])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `	return parent[v]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `	edges := []Edge{{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `		{'C', 'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `		{'G', 'H', 2}, {'H', 'E', 10}}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `	sort.Slice(edges, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `		return edges[i].weight < edges[j].weight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `	parent := [8]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `	for i := range parent {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `		parent[i] = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `	accepted, total, skipped := 0, 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `	for _, e := range edges {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `		if accepted == 7 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `			break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `		a, b := find(&parent, int(e.a-'A')), find(&parent, int(e.b-'A'))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `		if a == b {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `			skipped++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `			continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `		parent[a] = b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `		accepted++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **509 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 477 tokens. The contiguous original span L13–L42 costs 518 tokens; the complete original source costs 658 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L13: 487 tokens; removes `func find(parent *[8]int, v int) int {` from the dependency chain described above.
- Without L14: 495 tokens; removes `if parent[v] != v {` from the dependency chain described above.
- Without L15: 489 tokens; removes `parent[v] = find(parent, parent[v])` from the dependency chain described above.
- Without L16: 506 tokens; removes `}` from the dependency chain described above.
- Without L17: 501 tokens; removes `return parent[v]` from the dependency chain described above.
- Without L18: 507 tokens; removes `}` from the dependency chain described above.
- Without L21: 425 tokens; removes `edges := []Edge{{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6},` from the dependency chain described above.
- Without L22: 414 tokens; removes `{'C', 'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12},` from the dependency chain described above.
- Without L23: 476 tokens; removes `{'G', 'H', 2}, {'H', 'E', 10}}` from the dependency chain described above.
- Without L24: 487 tokens; removes `sort.Slice(edges, func(i, j int) bool {` from the dependency chain described above.
- Without L25: 491 tokens; removes `return edges[i].weight < edges[j].weight` from the dependency chain described above.
- Without L26: 505 tokens; removes `})` from the dependency chain described above.
- Without L27: 497 tokens; removes `parent := [8]int{}` from the dependency chain described above.
- Without L28: 496 tokens; removes `for i := range parent {` from the dependency chain described above.
- Without L29: 498 tokens; removes `parent[i] = i` from the dependency chain described above.
- Without L30: 506 tokens; removes `}` from the dependency chain described above.
- Without L31: 490 tokens; removes `accepted, total, skipped := 0, 0, 0` from the dependency chain described above.
- Without L32: 493 tokens; removes `for _, e := range edges {` from the dependency chain described above.
- Without L33: 497 tokens; removes `if accepted == 7 {` from the dependency chain described above.
- Without L34: 504 tokens; removes `break` from the dependency chain described above.
- Without L35: 505 tokens; removes `}` from the dependency chain described above.
- Without L36: 463 tokens; removes `a, b := find(&parent, int(e.a-'A')), find(&parent, int(e.b-'A'))` from the dependency chain described above.
- Without L37: 497 tokens; removes `if a == b {` from the dependency chain described above.
- Without L38: 503 tokens; removes `skipped++` from the dependency chain described above.
- Without L39: 504 tokens; removes `continue` from the dependency chain described above.
- Without L40: 505 tokens; removes `}` from the dependency chain described above.
- Without L41: 498 tokens; removes `parent[a] = b` from the dependency chain described above.
- Without L42: 504 tokens; removes `accepted++` from the dependency chain described above.
