# Task B selection: 90_kruskal_mst / Lua

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L18,L19,L20,L21,L22,L23,L24,L25,L26,L29.

- L1: `local edges = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    {"A", "B", 7}, {"C", "A", 4}, {"B", "C", 9}, {"B", "D", 14}, {"D", "C", 6}, {"C", "E", 3},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    {"E", "D", 5}, {"F", "D", 11}, {"E", "G", 16}, {"G", "F", 8}, {"H", "F", 12}, {"G", "H", 2},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    {"H", "E", 10},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `table.sort(edges, function(a, b) return a[3] < b[3] end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `local parents = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `for vertex in ("ABCDEFGH"):gmatch(".") do parents[vertex] = vertex end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `local function root(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    while parents[vertex] ~= vertex do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        parents[vertex] = parents[parents[vertex]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        vertex = parents[vertex]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    return vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `local accepted, skipped, total = 0, 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `for _, edge in ipairs(edges) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    local a, b, weight = table.unpack(edge)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    local first, second = root(a), root(b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    if first == second then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        skipped = skipped + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `        parents[second] = first` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        accepted, total = accepted + 1, total + weight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if accepted == 7 then break end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **496 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 491 tokens. The contiguous original span L1–L29 costs 557 tokens; the complete original source costs 596 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 488 tokens; removes `local edges = {` from the dependency chain described above.
- Without L2: 404 tokens; removes `{"A", "B", 7}, {"C", "A", 4}, {"B", "C", 9}, {"B", "D", 14}, {"D", "C", 6}, {"C", "E", 3},` from the dependency chain described above.
- Without L3: 402 tokens; removes `{"E", "D", 5}, {"F", "D", 11}, {"E", "G", 16}, {"G", "F", 8}, {"H", "F", 12}, {"G", "H", 2},` from the dependency chain described above.
- Without L4: 479 tokens; removes `{"H", "E", 10},` from the dependency chain described above.
- Without L6: 464 tokens; removes `table.sort(edges, function(a, b) return a[3] < b[3] end)` from the dependency chain described above.
- Without L7: 487 tokens; removes `local parents = {}` from the dependency chain described above.
- Without L8: 464 tokens; removes `for vertex in ("ABCDEFGH"):gmatch(".") do parents[vertex] = vertex end` from the dependency chain described above.
- Without L10: 487 tokens; removes `local function root(vertex)` from the dependency chain described above.
- Without L11: 482 tokens; removes `while parents[vertex] ~= vertex do` from the dependency chain described above.
- Without L12: 480 tokens; removes `parents[vertex] = parents[parents[vertex]]` from the dependency chain described above.
- Without L13: 485 tokens; removes `vertex = parents[vertex]` from the dependency chain described above.
- Without L14: 493 tokens; removes `end` from the dependency chain described above.
- Without L15: 491 tokens; removes `return vertex` from the dependency chain described above.
- Without L16: 494 tokens; removes `end` from the dependency chain described above.
- Without L18: 476 tokens; removes `local accepted, skipped, total = 0, 0, 0` from the dependency chain described above.
- Without L19: 480 tokens; removes `for _, edge in ipairs(edges) do` from the dependency chain described above.
- Without L20: 476 tokens; removes `local a, b, weight = table.unpack(edge)` from the dependency chain described above.
- Without L21: 475 tokens; removes `local first, second = root(a), root(b)` from the dependency chain described above.
- Without L22: 485 tokens; removes `if first == second then` from the dependency chain described above.
- Without L23: 484 tokens; removes `skipped = skipped + 1` from the dependency chain described above.
- Without L24: 493 tokens; removes `else` from the dependency chain described above.
- Without L25: 485 tokens; removes `parents[second] = first` from the dependency chain described above.
- Without L26: 474 tokens; removes `accepted, total = accepted + 1, total + weight` from the dependency chain described above.
- Without L29: 480 tokens; removes `if accepted == 7 then break end` from the dependency chain described above.
