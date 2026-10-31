# Task B selection: 90_kruskal_mst / Java

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `Main.java`. Selected original locations: L6,L7,L8,L9,L10,L11,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L28,L29,L31,L32.

- L6: `    static int find(int[] parent, int v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        if (parent[v] != v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `            parent[v] = find(parent, parent[v]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `        return parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `        int[][] edges = {{0, 1, 7}, {2, 0, 4}, {1, 2, 9}, {1, 3, 14}, {3, 2, 6}, {2, 4, 3}, {4, 3, 5},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            {5, 3, 11}, {4, 6, 16}, {6, 5, 8}, {7, 5, 12}, {6, 7, 2}, {7, 4, 10}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        Arrays.sort(edges, Comparator.comparingInt(e -> e[2]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        int[] parent = IntStream.range(0, 8).toArray();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        int accepted = 0, skipped = 0, total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        for (int[] edge : edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            int a = find(parent, edge[0]), b = find(parent, edge[1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            if (a == b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `                skipped++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `                continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `            parent[a] = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            accepted++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            char first = (char)('A' + Math.min(edge[0], edge[1]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            char second = (char)('A' + Math.max(edge[0], edge[1]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            if (accepted == 7) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `                break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **521 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 435 tokens. The contiguous original span L6–L32 costs 588 tokens; the complete original source costs 683 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 501 tokens; removes `static int find(int[] parent, int v) {` from the dependency chain described above.
- Without L7: 504 tokens; removes `if (parent[v] != v) {` from the dependency chain described above.
- Without L8: 499 tokens; removes `parent[v] = find(parent, parent[v]);` from the dependency chain described above.
- Without L9: 517 tokens; removes `}` from the dependency chain described above.
- Without L10: 511 tokens; removes `return parent[v];` from the dependency chain described above.
- Without L11: 518 tokens; removes `}` from the dependency chain described above.
- Without L14: 432 tokens; removes `int[][] edges = {{0, 1, 7}, {2, 0, 4}, {1, 2, 9}, {1, 3, 14}, {3, 2, 6}, {2, 4, 3}, {4, 3, 5},` from the dependency chain described above.
- Without L15: 447 tokens; removes `{5, 3, 11}, {4, 6, 16}, {6, 5, 8}, {7, 5, 12}, {6, 7, 2}, {7, 4, 10}};` from the dependency chain described above.
- Without L16: 495 tokens; removes `Arrays.sort(edges, Comparator.comparingInt(e -> e[2]));` from the dependency chain described above.
- Without L17: 495 tokens; removes `int[] parent = IntStream.range(0, 8).toArray();` from the dependency chain described above.
- Without L18: 496 tokens; removes `int accepted = 0, skipped = 0, total = 0;` from the dependency chain described above.
- Without L19: 504 tokens; removes `for (int[] edge : edges) {` from the dependency chain described above.
- Without L20: 484 tokens; removes `int a = find(parent, edge[0]), b = find(parent, edge[1]);` from the dependency chain described above.
- Without L21: 506 tokens; removes `if (a == b) {` from the dependency chain described above.
- Without L22: 513 tokens; removes `skipped++;` from the dependency chain described above.
- Without L23: 514 tokens; removes `continue;` from the dependency chain described above.
- Without L24: 516 tokens; removes `}` from the dependency chain described above.
- Without L25: 508 tokens; removes `parent[a] = b;` from the dependency chain described above.
- Without L26: 514 tokens; removes `accepted++;` from the dependency chain described above.
- Without L28: 484 tokens; removes `char first = (char)('A' + Math.min(edge[0], edge[1]));` from the dependency chain described above.
- Without L29: 484 tokens; removes `char second = (char)('A' + Math.max(edge[0], edge[1]));` from the dependency chain described above.
- Without L31: 506 tokens; removes `if (accepted == 7) {` from the dependency chain described above.
- Without L32: 514 tokens; removes `break;` from the dependency chain described above.
