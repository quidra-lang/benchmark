# Task B selection: 90_kruskal_mst / Swift

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.swift`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L26.

- L1: `func find(_ parent: inout [Int], _ v: Int) -> Int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    if parent[v] != v {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        let previous = parent[v]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        let root = find(&parent, previous)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        parent[v] = root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `    return parent[v]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `let edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    (0, 1, 7), (2, 0, 4), (1, 2, 9), (1, 3, 14), (3, 2, 6), (2, 4, 3), (4, 3, 5), (5, 3, 11),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    (4, 6, 16), (6, 5, 8), (7, 5, 12), (6, 7, 2), (7, 4, 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `var parent = Array(0..<8), accepted = 0, skipped = 0, total = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `let names = Array("ABCDEFGH")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `for (u, v, weight) in edges.sorted(by: { $0.2 < $1.2 }) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    let a = find(&parent, u), b = find(&parent, v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    if a == b {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        skipped += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    parent[a] = b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    accepted += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    if accepted == 7 { break }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **430 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 414 tokens. The contiguous original span L1–L26 costs 479 tokens; the complete original source costs 509 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 401 tokens; removes `func find(_ parent: inout [Int], _ v: Int) -> Int {` from the dependency chain described above.
- Without L2: 416 tokens; removes `if parent[v] != v {` from the dependency chain described above.
- Without L3: 417 tokens; removes `let previous = parent[v]` from the dependency chain described above.
- Without L4: 413 tokens; removes `let root = find(&parent, previous)` from the dependency chain described above.
- Without L5: 419 tokens; removes `parent[v] = root` from the dependency chain described above.
- Without L6: 427 tokens; removes `}` from the dependency chain described above.
- Without L7: 422 tokens; removes `return parent[v]` from the dependency chain described above.
- Without L8: 428 tokens; removes `}` from the dependency chain described above.
- Without L10: 422 tokens; removes `let edges = [` from the dependency chain described above.
- Without L11: 339 tokens; removes `(0, 1, 7), (2, 0, 4), (1, 2, 9), (1, 3, 14), (3, 2, 6), (2, 4, 3), (4, 3, 5), (5, 3, 11),` from the dependency chain described above.
- Without L12: 371 tokens; removes `(4, 6, 16), (6, 5, 8), (7, 5, 12), (6, 7, 2), (7, 4, 10),` from the dependency chain described above.
- Without L14: 396 tokens; removes `var parent = Array(0..<8), accepted = 0, skipped = 0, total = 0` from the dependency chain described above.
- Without L15: 417 tokens; removes `let names = Array("ABCDEFGH")` from the dependency chain described above.
- Without L16: 390 tokens; removes `for (u, v, weight) in edges.sorted(by: { $0.2 < $1.2 }) {` from the dependency chain described above.
- Without L17: 400 tokens; removes `let a = find(&parent, u), b = find(&parent, v)` from the dependency chain described above.
- Without L18: 419 tokens; removes `if a == b {` from the dependency chain described above.
- Without L19: 422 tokens; removes `skipped += 1` from the dependency chain described above.
- Without L20: 426 tokens; removes `continue` from the dependency chain described above.
- Without L21: 427 tokens; removes `}` from the dependency chain described above.
- Without L22: 420 tokens; removes `parent[a] = b` from the dependency chain described above.
- Without L23: 423 tokens; removes `accepted += 1` from the dependency chain described above.
- Without L26: 415 tokens; removes `if accepted == 7 { break }` from the dependency chain described above.
