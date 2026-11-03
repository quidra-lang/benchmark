# Task B selection: 90_kruskal_mst / Dart

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.dart`. Selected original locations: L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L28,L29,L30,L31,L32,L33,L34,L35,L36,L39,L41.

- L4: `  final edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    (0, 1, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (2, 0, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    (1, 2, 9),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    (1, 3, 14),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    (3, 2, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    (2, 4, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    (4, 3, 5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    (5, 3, 11),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    (4, 6, 16),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    (6, 5, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    (7, 5, 12),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    (6, 7, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    (7, 4, 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  ]..sort((a, b) => a.$3.compareTo(b.$3));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  final parent = List.generate(8, (i) => i);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  int find(int v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    while (parent[v] != v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `      parent[v] = parent[parent[v]];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `      v = parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `    return v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `  var accepted = 0, skipped = 0, total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  for (final e in edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    final a = find(e.$1), b = find(e.$2);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    if (a == b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `      skipped++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `      continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    parent[a] = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    accepted++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `      '${String.fromCharCode(65 + math.min(e.$1, e.$2))}-${String.fromCharCode(65 + math.max(e.$1, e.$2))} ${e.$3}',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    if (accepted == 7) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **484 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 405 tokens. The contiguous original span L4–L41 costs 503 tokens; the complete original source costs 551 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L4: 475 tokens; removes `final edges = [` from the dependency chain described above.
- Without L5: 472 tokens; removes `(0, 1, 7),` from the dependency chain described above.
- Without L6: 472 tokens; removes `(2, 0, 4),` from the dependency chain described above.
- Without L7: 472 tokens; removes `(1, 2, 9),` from the dependency chain described above.
- Without L8: 471 tokens; removes `(1, 3, 14),` from the dependency chain described above.
- Without L9: 472 tokens; removes `(3, 2, 6),` from the dependency chain described above.
- Without L10: 472 tokens; removes `(2, 4, 3),` from the dependency chain described above.
- Without L11: 472 tokens; removes `(4, 3, 5),` from the dependency chain described above.
- Without L12: 471 tokens; removes `(5, 3, 11),` from the dependency chain described above.
- Without L13: 471 tokens; removes `(4, 6, 16),` from the dependency chain described above.
- Without L14: 472 tokens; removes `(6, 5, 8),` from the dependency chain described above.
- Without L15: 471 tokens; removes `(7, 5, 12),` from the dependency chain described above.
- Without L16: 472 tokens; removes `(6, 7, 2),` from the dependency chain described above.
- Without L17: 471 tokens; removes `(7, 4, 10),` from the dependency chain described above.
- Without L18: 456 tokens; removes `]..sort((a, b) => a.$3.compareTo(b.$3));` from the dependency chain described above.
- Without L19: 460 tokens; removes `final parent = List.generate(8, (i) => i);` from the dependency chain described above.
- Without L20: 472 tokens; removes `int find(int v) {` from the dependency chain described above.
- Without L21: 468 tokens; removes `while (parent[v] != v) {` from the dependency chain described above.
- Without L22: 467 tokens; removes `parent[v] = parent[parent[v]];` from the dependency chain described above.
- Without L23: 472 tokens; removes `v = parent[v];` from the dependency chain described above.
- Without L24: 481 tokens; removes `}` from the dependency chain described above.
- Without L25: 478 tokens; removes `return v;` from the dependency chain described above.
- Without L26: 481 tokens; removes `}` from the dependency chain described above.
- Without L28: 460 tokens; removes `var accepted = 0, skipped = 0, total = 0;` from the dependency chain described above.
- Without L29: 469 tokens; removes `for (final e in edges) {` from the dependency chain described above.
- Without L30: 457 tokens; removes `final a = find(e.$1), b = find(e.$2);` from the dependency chain described above.
- Without L31: 471 tokens; removes `if (a == b) {` from the dependency chain described above.
- Without L32: 478 tokens; removes `skipped++;` from the dependency chain described above.
- Without L33: 479 tokens; removes `continue;` from the dependency chain described above.
- Without L34: 481 tokens; removes `}` from the dependency chain described above.
- Without L35: 473 tokens; removes `parent[a] = b;` from the dependency chain described above.
- Without L36: 479 tokens; removes `accepted++;` from the dependency chain described above.
- Without L39: 414 tokens; removes `'${String.fromCharCode(65 + math.min(e.$1, e.$2))}-${String.fromCharCode(65 + math.max(e.$1, e.$2))} ${e.$3}',` from the dependency chain described above.
- Without L41: 470 tokens; removes `if (accepted == 7) break;` from the dependency chain described above.
