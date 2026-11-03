# Task B selection: 90_kruskal_mst / C++

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.cpp`. Selected original locations: L12,L13,L14,L15,L16,L19,L20,L21,L22,L23,L24,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37.

- L12: `int find(std::array<int, 8> &parent, int v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    if (parent[v] != v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        parent[v] = find(parent, parent[v]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    return parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    std::vector<Edge> edges = {{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        {'C', 'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        {'G', 'H', 2}, {'H', 'E', 10}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    std::sort(edges.begin(), edges.end(), [](const Edge &a, const Edge &b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        return a.weight < b.weight;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    std::iota(parent.begin(), parent.end(), 0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    int accepted = 0, total = 0, skipped = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    for (const Edge &e : edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if (accepted == 7)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        int a = find(parent, e.a - 'A'), b = find(parent, e.b - 'A');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        if (a == b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            ++skipped;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `        parent[a] = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        ++accepted;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **526 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 515 tokens. The contiguous original span L12–L37 costs 549 tokens; the complete original source costs 730 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L12: 501 tokens; removes `int find(std::array<int, 8> &parent, int v) {` from the dependency chain described above.
- Without L13: 512 tokens; removes `if (parent[v] != v)` from the dependency chain described above.
- Without L14: 505 tokens; removes `parent[v] = find(parent, parent[v]);` from the dependency chain described above.
- Without L15: 517 tokens; removes `return parent[v];` from the dependency chain described above.
- Without L16: 524 tokens; removes `}` from the dependency chain described above.
- Without L19: 437 tokens; removes `std::vector<Edge> edges = {{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6},` from the dependency chain described above.
- Without L20: 431 tokens; removes `{'C', 'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12},` from the dependency chain described above.
- Without L21: 492 tokens; removes `{'G', 'H', 2}, {'H', 'E', 10}};` from the dependency chain described above.
- Without L22: 487 tokens; removes `std::sort(edges.begin(), edges.end(), [](const Edge &a, const Edge &b) {` from the dependency chain described above.
- Without L23: 511 tokens; removes `return a.weight < b.weight;` from the dependency chain described above.
- Without L24: 521 tokens; removes `});` from the dependency chain described above.
- Without L26: 503 tokens; removes `std::iota(parent.begin(), parent.end(), 0);` from the dependency chain described above.
- Without L27: 502 tokens; removes `int accepted = 0, total = 0, skipped = 0;` from the dependency chain described above.
- Without L28: 508 tokens; removes `for (const Edge &e : edges) {` from the dependency chain described above.
- Without L29: 514 tokens; removes `if (accepted == 7)` from the dependency chain described above.
- Without L30: 520 tokens; removes `break;` from the dependency chain described above.
- Without L31: 480 tokens; removes `int a = find(parent, e.a - 'A'), b = find(parent, e.b - 'A');` from the dependency chain described above.
- Without L32: 512 tokens; removes `if (a == b) {` from the dependency chain described above.
- Without L33: 519 tokens; removes `++skipped;` from the dependency chain described above.
- Without L34: 520 tokens; removes `continue;` from the dependency chain described above.
- Without L35: 522 tokens; removes `}` from the dependency chain described above.
- Without L36: 514 tokens; removes `parent[a] = b;` from the dependency chain described above.
- Without L37: 520 tokens; removes `++accepted;` from the dependency chain described above.
