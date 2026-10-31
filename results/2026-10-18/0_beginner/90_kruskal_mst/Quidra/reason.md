# Task B selection: 90_kruskal_mst / Quidra

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.qui`. Selected original locations: L1,L2,L3,L4,L6,L7,L8,L9,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L22,L23,L24,L25,L26,L27,L28,L33,L34,L35.

- L1: `int root(int vertex, int[] parent)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    while parent[vertex] != vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        vertex = parent[vertex]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    return vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `string names = "ABCDEFGH"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `int[][] edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    [0, 1, 7], [2, 0, 4], [1, 2, 9], [1, 3, 14], [3, 2, 6], [2, 4, 3], [4, 3, 5], [5, 3, 11],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    [4, 6, 16], [6, 5, 8], [7, 5, 12], [6, 7, 2], [7, 4, 10],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `for 1 <= int i < int(len(edges))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    int[] edge = edges[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    int j = i - 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    while j >= 0 and edges[j][2] > edge[2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        edges[j + 1] = edges[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        j -= 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    edges[j + 1] = edge` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `int[] parent = 0:7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `int accepted = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `int skipped = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `for int[] edge = edges[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    int first = root(edge[0], parent)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    int second = root(edge[1], parent)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    if first == second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        skipped += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    parent[second] = first` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    accepted += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    if accepted == 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **451 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 441 tokens. The contiguous original span L1–L35 costs 572 tokens; the complete original source costs 598 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 436 tokens; removes `int root(int vertex, int[] parent)` from the dependency chain described above.
- Without L2: 439 tokens; removes `while parent[vertex] != vertex` from the dependency chain described above.
- Without L3: 440 tokens; removes `vertex = parent[vertex]` from the dependency chain described above.
- Without L4: 446 tokens; removes `return vertex` from the dependency chain described above.
- Without L6: 441 tokens; removes `string names = "ABCDEFGH"` from the dependency chain described above.
- Without L7: 441 tokens; removes `int[][] edges = [` from the dependency chain described above.
- Without L8: 360 tokens; removes `[0, 1, 7], [2, 0, 4], [1, 2, 9], [1, 3, 14], [3, 2, 6], [2, 4, 3], [4, 3, 5], [5, 3, 11],` from the dependency chain described above.
- Without L9: 392 tokens; removes `[4, 6, 16], [6, 5, 8], [7, 5, 12], [6, 7, 2], [7, 4, 10],` from the dependency chain described above.
- Without L11: 431 tokens; removes `for 1 <= int i < int(len(edges))` from the dependency chain described above.
- Without L12: 438 tokens; removes `int[] edge = edges[i]` from the dependency chain described above.
- Without L13: 438 tokens; removes `int j = i - 1` from the dependency chain described above.
- Without L14: 425 tokens; removes `while j >= 0 and edges[j][2] > edge[2]` from the dependency chain described above.
- Without L15: 433 tokens; removes `edges[j + 1] = edges[j]` from the dependency chain described above.
- Without L16: 443 tokens; removes `j -= 1` from the dependency chain described above.
- Without L17: 437 tokens; removes `edges[j + 1] = edge` from the dependency chain described above.
- Without L18: 440 tokens; removes `int[] parent = 0:7` from the dependency chain described above.
- Without L19: 443 tokens; removes `int accepted = 0` from the dependency chain described above.
- Without L20: 443 tokens; removes `int skipped = 0` from the dependency chain described above.
- Without L22: 439 tokens; removes `for int[] edge = edges[]` from the dependency chain described above.
- Without L23: 433 tokens; removes `int first = root(edge[0], parent)` from the dependency chain described above.
- Without L24: 433 tokens; removes `int second = root(edge[1], parent)` from the dependency chain described above.
- Without L25: 442 tokens; removes `if first == second` from the dependency chain described above.
- Without L26: 443 tokens; removes `skipped += 1` from the dependency chain described above.
- Without L27: 447 tokens; removes `continue` from the dependency chain described above.
- Without L28: 441 tokens; removes `parent[second] = first` from the dependency chain described above.
- Without L33: 444 tokens; removes `accepted += 1` from the dependency chain described above.
- Without L34: 442 tokens; removes `if accepted == 7` from the dependency chain described above.
- Without L35: 447 tokens; removes `break` from the dependency chain described above.
