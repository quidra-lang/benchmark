# Task B selection: 90_kruskal_mst / Kotlin

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.kt`. Selected original locations: L1,L2,L3,L4,L7,L8,L9,L10,L12,L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L27.

- L1: `fun find(parent: IntArray, v: Int): Int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    if (parent[v] != v) parent[v] = find(parent, parent[v])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    return parent[v]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `    val edges = listOf(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        Triple(0, 1, 7), Triple(2, 0, 4), Triple(1, 2, 9), Triple(1, 3, 14), Triple(3, 2, 6), Triple(2, 4, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        Triple(4, 3, 5), Triple(5, 3, 11), Triple(4, 6, 16), Triple(6, 5, 8), Triple(7, 5, 12), Triple(6, 7, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        Triple(7, 4, 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    val parent = IntArray(8) { it }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    var accepted = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    var skipped = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    for ((u, v, weight) in edges.sortedBy { it.third }) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        val a = find(parent, u)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        val b = find(parent, v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        if (a == b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            skipped++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `        parent[a] = b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        accepted++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        println("${'A' + minOf(u, v)}-${'A' + maxOf(u, v)} $weight")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        if (accepted == 7) break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **447 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 384 tokens. The contiguous original span L1–L27 costs 476 tokens; the complete original source costs 507 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 426 tokens; removes `fun find(parent: IntArray, v: Int): Int {` from the dependency chain described above.
- Without L2: 415 tokens; removes `if (parent[v] != v) parent[v] = find(parent, parent[v])` from the dependency chain described above.
- Without L3: 439 tokens; removes `return parent[v]` from the dependency chain described above.
- Without L4: 445 tokens; removes `}` from the dependency chain described above.
- Without L7: 436 tokens; removes `val edges = listOf(` from the dependency chain described above.
- Without L8: 372 tokens; removes `Triple(0, 1, 7), Triple(2, 0, 4), Triple(1, 2, 9), Triple(1, 3, 14), Triple(3, 2, 6), Triple(2, 4, 3),` from the dependency chain described above.
- Without L9: 370 tokens; removes `Triple(4, 3, 5), Triple(5, 3, 11), Triple(4, 6, 16), Triple(6, 5, 8), Triple(7, 5, 12), Triple(6, 7, 2),` from the dependency chain described above.
- Without L10: 432 tokens; removes `Triple(7, 4, 10),` from the dependency chain described above.
- Without L12: 428 tokens; removes `val parent = IntArray(8) { it }` from the dependency chain described above.
- Without L13: 438 tokens; removes `var accepted = 0` from the dependency chain described above.
- Without L14: 438 tokens; removes `var skipped = 0` from the dependency chain described above.
- Without L16: 415 tokens; removes `for ((u, v, weight) in edges.sortedBy { it.third }) {` from the dependency chain described above.
- Without L17: 431 tokens; removes `val a = find(parent, u)` from the dependency chain described above.
- Without L18: 431 tokens; removes `val b = find(parent, v)` from the dependency chain described above.
- Without L19: 433 tokens; removes `if (a == b) {` from the dependency chain described above.
- Without L20: 441 tokens; removes `skipped++` from the dependency chain described above.
- Without L21: 442 tokens; removes `continue` from the dependency chain described above.
- Without L22: 443 tokens; removes `}` from the dependency chain described above.
- Without L23: 436 tokens; removes `parent[a] = b` from the dependency chain described above.
- Without L24: 442 tokens; removes `accepted++` from the dependency chain described above.
- Without L26: 401 tokens; removes `println("${'A' + minOf(u, v)}-${'A' + maxOf(u, v)} $weight")` from the dependency chain described above.
- Without L27: 433 tokens; removes `if (accepted == 7) break` from the dependency chain described above.
