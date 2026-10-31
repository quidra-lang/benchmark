# Task B selection: 90_kruskal_mst / J

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.ijs`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L20,L21.

- L1: `root =: 3 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  vertex =. y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  while. vertex~:vertex{parent do. vertex =. vertex{parent end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `  names =. 'ABCDEFGH'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  edges =. 13 3$0 1 7 2 0 4 1 2 9 1 3 14 3 2 6 2 4 3 4 3 5 5 3 11 4 6 16 6 5 8 7 5 12 6 7 2 7 4 10` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  edges =. edges {~ /:2{"1 edges` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  parent =: i.8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  accepted =. skipped =. total =. 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  for_edge. edges do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    'a b weight' =. edge` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    first =. root a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    second =. root b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    if. first=second do. skipped =. >:skipped continue. end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    parent =: first second}parent` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    accepted =. >:accepted` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    if. accepted=7 do. break. end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **279 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 277 tokens. The contiguous original span L1–L21 costs 333 tokens; the complete original source costs 371 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 269 tokens; removes `root =: 3 : 0` from the dependency chain described above.
- Without L2: 272 tokens; removes `vertex =. y` from the dependency chain described above.
- Without L3: 258 tokens; removes `while. vertex~:vertex{parent do. vertex =. vertex{parent end.` from the dependency chain described above.
- Without L4: 276 tokens; removes `vertex` from the dependency chain described above.
- Without L5: 277 tokens; removes `)` from the dependency chain described above.
- Without L7: 270 tokens; removes `names =. 'ABCDEFGH'` from the dependency chain described above.
- Without L8: 186 tokens; removes `edges =. 13 3$0 1 7 2 0 4 1 2 9 1 3 14 3 2 6 2 4 3 4 3 5 5 3 11 4 6 16 6 5 8 7 5 12 6 7 2 7 4 10` from the dependency chain described above.
- Without L9: 261 tokens; removes `edges =. edges {~ /:2{"1 edges` from the dependency chain described above.
- Without L10: 271 tokens; removes `parent =: i.8` from the dependency chain described above.
- Without L11: 264 tokens; removes `accepted =. skipped =. total =. 0` from the dependency chain described above.
- Without L12: 269 tokens; removes `for_edge. edges do.` from the dependency chain described above.
- Without L13: 266 tokens; removes `'a b weight' =. edge` from the dependency chain described above.
- Without L14: 270 tokens; removes `first =. root a` from the dependency chain described above.
- Without L15: 270 tokens; removes `second =. root b` from the dependency chain described above.
- Without L16: 259 tokens; removes `if. first=second do. skipped =. >:skipped continue. end.` from the dependency chain described above.
- Without L17: 268 tokens; removes `parent =: first second}parent` from the dependency chain described above.
- Without L20: 271 tokens; removes `accepted =. >:accepted` from the dependency chain described above.
- Without L21: 266 tokens; removes `if. accepted=7 do. break. end.` from the dependency chain described above.
