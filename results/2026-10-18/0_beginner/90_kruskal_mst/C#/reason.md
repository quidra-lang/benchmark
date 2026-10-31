# Task B selection: 90_kruskal_mst / C#

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `Program.cs`. Selected original locations: L7,L8,L9,L10,L11,L13,L14,L15,L16,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L31,L33.

- L7: `static int Find(int[] parent, int v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `    if (parent[v] != v) parent[v] = Find(parent, parent[v]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    return parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `var edges = new[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    (0, 1, 7), (2, 0, 4), (1, 2, 9), (1, 3, 14), (3, 2, 6), (2, 4, 3), (4, 3, 5), (5, 3, 11),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    (4, 6, 16), (6, 5, 8), (7, 5, 12), (6, 7, 2), (7, 4, 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `int[] parent = Enumerable.Range(0, 8).ToArray();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `int accepted = 0, skipped = 0, total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `foreach (var (u, v, weight) in edges.OrderBy(e => e.Item3))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    int a = Find(parent, u), b = Find(parent, v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    if (a == b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `        skipped++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    parent[a] = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    accepted++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    char first = (char)('A' + Math.Min(u, v)), second = (char)('A' + Math.Max(u, v));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    if (accepted == 7) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **446 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 371 tokens. The contiguous original span L7–L33 costs 481 tokens; the complete original source costs 555 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 429 tokens; removes `static int Find(int[] parent, int v)` from the dependency chain described above.
- Without L8: 444 tokens; removes `{` from the dependency chain described above.
- Without L9: 413 tokens; removes `if (parent[v] != v) parent[v] = Find(parent, parent[v]);` from the dependency chain described above.
- Without L10: 437 tokens; removes `return parent[v];` from the dependency chain described above.
- Without L11: 444 tokens; removes `}` from the dependency chain described above.
- Without L13: 437 tokens; removes `var edges = new[]` from the dependency chain described above.
- Without L14: 444 tokens; removes `{` from the dependency chain described above.
- Without L15: 355 tokens; removes `(0, 1, 7), (2, 0, 4), (1, 2, 9), (1, 3, 14), (3, 2, 6), (2, 4, 3), (4, 3, 5), (5, 3, 11),` from the dependency chain described above.
- Without L16: 387 tokens; removes `(4, 6, 16), (6, 5, 8), (7, 5, 12), (6, 7, 2), (7, 4, 10),` from the dependency chain described above.
- Without L18: 423 tokens; removes `int[] parent = Enumerable.Range(0, 8).ToArray();` from the dependency chain described above.
- Without L19: 423 tokens; removes `int accepted = 0, skipped = 0, total = 0;` from the dependency chain described above.
- Without L20: 414 tokens; removes `foreach (var (u, v, weight) in edges.OrderBy(e => e.Item3))` from the dependency chain described above.
- Without L21: 444 tokens; removes `{` from the dependency chain described above.
- Without L22: 417 tokens; removes `int a = Find(parent, u), b = Find(parent, v);` from the dependency chain described above.
- Without L23: 435 tokens; removes `if (a == b)` from the dependency chain described above.
- Without L24: 443 tokens; removes `{` from the dependency chain described above.
- Without L25: 440 tokens; removes `skipped++;` from the dependency chain described above.
- Without L26: 441 tokens; removes `continue;` from the dependency chain described above.
- Without L27: 443 tokens; removes `}` from the dependency chain described above.
- Without L28: 435 tokens; removes `parent[a] = b;` from the dependency chain described above.
- Without L29: 441 tokens; removes `accepted++;` from the dependency chain described above.
- Without L31: 391 tokens; removes `char first = (char)('A' + Math.Min(u, v)), second = (char)('A' + Math.Max(u, v));` from the dependency chain described above.
- Without L33: 432 tokens; removes `if (accepted == 7) break;` from the dependency chain described above.
