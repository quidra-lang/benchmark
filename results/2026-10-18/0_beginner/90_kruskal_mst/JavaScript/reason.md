# Task B selection: 90_kruskal_mst / JavaScript

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.js`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L11,L13,L14,L15,L16,L17,L18,L19,L21,L22,L23,L24,L25,L26,L27,L28,L29,L32.

- L1: `const vertices = "ABCDEFGH";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `const edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  {a: "A", b: "B", weight: 7}, {a: "C", b: "A", weight: 4},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  {a: "B", b: "C", weight: 9}, {a: "B", b: "D", weight: 14},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  {a: "D", b: "C", weight: 6}, {a: "C", b: "E", weight: 3},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  {a: "E", b: "D", weight: 5}, {a: "F", b: "D", weight: 11},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  {a: "E", b: "G", weight: 16}, {a: "G", b: "F", weight: 8},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  {a: "H", b: "F", weight: 12}, {a: "G", b: "H", weight: 2},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  {a: "H", b: "E", weight: 10}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `const parent = new Map([...vertices].map(vertex => [vertex, vertex]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `function find(vertex) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  while (parent.get(vertex) !== vertex) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    parent.set(vertex, parent.get(parent.get(vertex)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    vertex = parent.get(vertex);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `  return vertex;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `let accepted = 0, skipped = 0, total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `for (const {a, b, weight} of edges.sort((a, b) => a.weight - b.weight)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  const rootA = find(a), rootB = find(b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  if (rootA === rootB) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    skipped++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `  parent.set(rootB, rootA);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  accepted++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  if (accepted === vertices.length - 1) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **577 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 569 tokens. The contiguous original span L1–L32 costs 624 tokens; the complete original source costs 660 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 566 tokens; removes `const vertices = "ABCDEFGH";` from the dependency chain described above.
- Without L2: 569 tokens; removes `const edges = [` from the dependency chain described above.
- Without L3: 532 tokens; removes `{a: "A", b: "B", weight: 7}, {a: "C", b: "A", weight: 4},` from the dependency chain described above.
- Without L4: 531 tokens; removes `{a: "B", b: "C", weight: 9}, {a: "B", b: "D", weight: 14},` from the dependency chain described above.
- Without L5: 532 tokens; removes `{a: "D", b: "C", weight: 6}, {a: "C", b: "E", weight: 3},` from the dependency chain described above.
- Without L6: 531 tokens; removes `{a: "E", b: "D", weight: 5}, {a: "F", b: "D", weight: 11},` from the dependency chain described above.
- Without L7: 531 tokens; removes `{a: "E", b: "G", weight: 16}, {a: "G", b: "F", weight: 8},` from the dependency chain described above.
- Without L8: 531 tokens; removes `{a: "H", b: "F", weight: 12}, {a: "G", b: "H", weight: 2},` from the dependency chain described above.
- Without L9: 554 tokens; removes `{a: "H", b: "E", weight: 10}` from the dependency chain described above.
- Without L11: 547 tokens; removes `const parent = new Map([...vertices].map(vertex => [vertex, vertex]));` from the dependency chain described above.
- Without L13: 568 tokens; removes `function find(vertex) {` from the dependency chain described above.
- Without L14: 559 tokens; removes `while (parent.get(vertex) !== vertex) {` from the dependency chain described above.
- Without L15: 555 tokens; removes `parent.set(vertex, parent.get(parent.get(vertex)));` from the dependency chain described above.
- Without L16: 564 tokens; removes `vertex = parent.get(vertex);` from the dependency chain described above.
- Without L17: 574 tokens; removes `}` from the dependency chain described above.
- Without L18: 571 tokens; removes `return vertex;` from the dependency chain described above.
- Without L19: 575 tokens; removes `}` from the dependency chain described above.
- Without L21: 554 tokens; removes `let accepted = 0, skipped = 0, total = 0;` from the dependency chain described above.
- Without L22: 533 tokens; removes `for (const {a, b, weight} of edges.sort((a, b) => a.weight - b.weight)) {` from the dependency chain described above.
- Without L23: 552 tokens; removes `const rootA = find(a), rootB = find(b);` from the dependency chain described above.
- Without L24: 562 tokens; removes `if (rootA === rootB) {` from the dependency chain described above.
- Without L25: 572 tokens; removes `skipped++;` from the dependency chain described above.
- Without L26: 573 tokens; removes `continue;` from the dependency chain described above.
- Without L27: 574 tokens; removes `}` from the dependency chain described above.
- Without L28: 563 tokens; removes `parent.set(rootB, rootA);` from the dependency chain described above.
- Without L29: 572 tokens; removes `accepted++;` from the dependency chain described above.
- Without L32: 557 tokens; removes `if (accepted === vertices.length - 1) break;` from the dependency chain described above.
