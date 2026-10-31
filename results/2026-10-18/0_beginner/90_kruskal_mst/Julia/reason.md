# Task B selection: 90_kruskal_mst / Julia

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.jl`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L38.

- L1: `function root!(parents, vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    while parents[vertex] != vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        parents[vertex] = parents[parents[vertex]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        vertex = parents[vertex]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `    return vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        ('A', 'B', 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        ('C', 'A', 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        ('B', 'C', 9),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        ('B', 'D', 14),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        ('D', 'C', 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        ('C', 'E', 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        ('E', 'D', 5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        ('F', 'D', 11),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        ('E', 'G', 16),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        ('G', 'F', 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        ('H', 'F', 12),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        ('G', 'H', 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        ('H', 'E', 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    sort!(edges; by = edge -> edge[3])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    parents = collect(1:8)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    accepted, skipped, total = 0, 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    for (a, b, weight) in edges` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        first_root = root!(parents, Int(a)-Int('A')+1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        second_root = root!(parents, Int(b)-Int('A')+1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        if first_root == second_root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            skipped += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `            parents[second_root] = first_root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            accepted += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            accepted == 7 && break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **485 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 473 tokens. The contiguous original span L1–L38 costs 540 tokens; the complete original source costs 582 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 474 tokens; removes `function root!(parents, vertex)` from the dependency chain described above.
- Without L2: 473 tokens; removes `while parents[vertex] != vertex` from the dependency chain described above.
- Without L3: 469 tokens; removes `parents[vertex] = parents[parents[vertex]]` from the dependency chain described above.
- Without L4: 474 tokens; removes `vertex = parents[vertex]` from the dependency chain described above.
- Without L5: 482 tokens; removes `end` from the dependency chain described above.
- Without L6: 480 tokens; removes `return vertex` from the dependency chain described above.
- Without L7: 483 tokens; removes `end` from the dependency chain described above.
- Without L10: 478 tokens; removes `edges = [` from the dependency chain described above.
- Without L11: 468 tokens; removes `('A', 'B', 7),` from the dependency chain described above.
- Without L12: 468 tokens; removes `('C', 'A', 4),` from the dependency chain described above.
- Without L13: 468 tokens; removes `('B', 'C', 9),` from the dependency chain described above.
- Without L14: 467 tokens; removes `('B', 'D', 14),` from the dependency chain described above.
- Without L15: 468 tokens; removes `('D', 'C', 6),` from the dependency chain described above.
- Without L16: 468 tokens; removes `('C', 'E', 3),` from the dependency chain described above.
- Without L17: 468 tokens; removes `('E', 'D', 5),` from the dependency chain described above.
- Without L18: 467 tokens; removes `('F', 'D', 11),` from the dependency chain described above.
- Without L19: 467 tokens; removes `('E', 'G', 16),` from the dependency chain described above.
- Without L20: 468 tokens; removes `('G', 'F', 8),` from the dependency chain described above.
- Without L21: 467 tokens; removes `('H', 'F', 12),` from the dependency chain described above.
- Without L22: 468 tokens; removes `('G', 'H', 2),` from the dependency chain described above.
- Without L23: 467 tokens; removes `('H', 'E', 10),` from the dependency chain described above.
- Without L25: 464 tokens; removes `sort!(edges; by = edge -> edge[3])` from the dependency chain described above.
- Without L26: 473 tokens; removes `parents = collect(1:8)` from the dependency chain described above.
- Without L27: 466 tokens; removes `accepted, skipped, total = 0, 0, 0` from the dependency chain described above.
- Without L28: 468 tokens; removes `for (a, b, weight) in edges` from the dependency chain described above.
- Without L29: 456 tokens; removes `first_root = root!(parents, Int(a)-Int('A')+1)` from the dependency chain described above.
- Without L30: 456 tokens; removes `second_root = root!(parents, Int(b)-Int('A')+1)` from the dependency chain described above.
- Without L31: 471 tokens; removes `if first_root == second_root` from the dependency chain described above.
- Without L32: 476 tokens; removes `skipped += 1` from the dependency chain described above.
- Without L33: 481 tokens; removes `else` from the dependency chain described above.
- Without L34: 469 tokens; removes `parents[second_root] = first_root` from the dependency chain described above.
- Without L35: 476 tokens; removes `accepted += 1` from the dependency chain described above.
- Without L38: 472 tokens; removes `accepted == 7 && break` from the dependency chain described above.
