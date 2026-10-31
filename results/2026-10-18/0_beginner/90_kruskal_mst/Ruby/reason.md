# Task B selection: 90_kruskal_mst / Ruby

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.rb`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L26.

- L1: `vertices = 'ABCDEFGH'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  ['A', 'B', 7], ['C', 'A', 4], ['B', 'C', 9], ['B', 'D', 14], ['D', 'C', 6],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  ['C', 'E', 3], ['E', 'D', 5], ['F', 'D', 11], ['E', 'G', 16], ['G', 'F', 8],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  ['H', 'F', 12], ['G', 'H', 2], ['H', 'E', 10]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `parent = vertices.chars.to_h { |vertex| [vertex, vertex] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `find = lambda do |vertex|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  while parent[vertex] != vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    parent[vertex] = parent[parent[vertex]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    vertex = parent[vertex]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `  vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `accepted = skipped = total = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `edges.sort_by(&:last).each do |a, b, weight|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  root_a, root_b = find.call(a), find.call(b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  if root_a == root_b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    skipped += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    next` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `  parent[root_b] = root_a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  accepted += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `  break if accepted == vertices.length - 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **429 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 421 tokens. The contiguous original span L1–L26 costs 466 tokens; the complete original source costs 494 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 421 tokens; removes `vertices = 'ABCDEFGH'` from the dependency chain described above.
- Without L2: 423 tokens; removes `edges = [` from the dependency chain described above.
- Without L3: 352 tokens; removes `['A', 'B', 7], ['C', 'A', 4], ['B', 'C', 9], ['B', 'D', 14], ['D', 'C', 6],` from the dependency chain described above.
- Without L4: 351 tokens; removes `['C', 'E', 3], ['E', 'D', 5], ['F', 'D', 11], ['E', 'G', 16], ['G', 'F', 8],` from the dependency chain described above.
- Without L5: 382 tokens; removes `['H', 'F', 12], ['G', 'H', 2], ['H', 'E', 10]` from the dependency chain described above.
- Without L7: 402 tokens; removes `parent = vertices.chars.to_h { |vertex| [vertex, vertex] }` from the dependency chain described above.
- Without L8: 417 tokens; removes `find = lambda do |vertex|` from the dependency chain described above.
- Without L9: 417 tokens; removes `while parent[vertex] != vertex` from the dependency chain described above.
- Without L10: 414 tokens; removes `parent[vertex] = parent[parent[vertex]]` from the dependency chain described above.
- Without L11: 419 tokens; removes `vertex = parent[vertex]` from the dependency chain described above.
- Without L12: 426 tokens; removes `end` from the dependency chain described above.
- Without L13: 426 tokens; removes `vertex` from the dependency chain described above.
- Without L14: 427 tokens; removes `end` from the dependency chain described above.
- Without L15: 415 tokens; removes `accepted = skipped = total = 0` from the dependency chain described above.
- Without L16: 405 tokens; removes `edges.sort_by(&:last).each do |a, b, weight|` from the dependency chain described above.
- Without L17: 402 tokens; removes `root_a, root_b = find.call(a), find.call(b)` from the dependency chain described above.
- Without L18: 416 tokens; removes `if root_a == root_b` from the dependency chain described above.
- Without L19: 422 tokens; removes `skipped += 1` from the dependency chain described above.
- Without L20: 426 tokens; removes `next` from the dependency chain described above.
- Without L21: 426 tokens; removes `end` from the dependency chain described above.
- Without L22: 415 tokens; removes `parent[root_b] = root_a` from the dependency chain described above.
- Without L23: 422 tokens; removes `accepted += 1` from the dependency chain described above.
- Without L26: 412 tokens; removes `break if accepted == vertices.length - 1` from the dependency chain described above.
