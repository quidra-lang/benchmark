# Task B selection: 90_kruskal_mst / PHP

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L8,L9,L11,L12,L13,L14,L15,L16,L17,L18,L20,L21,L22,L23,L24,L25,L26,L27,L28,L33,L34.

- L3: `$edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    ['A', 'B', 7], ['C', 'A', 4], ['B', 'C', 9], ['B', 'D', 14], ['D', 'C', 6], ['C', 'E', 3],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    ['E', 'D', 5], ['F', 'D', 11], ['E', 'G', 16], ['G', 'F', 8], ['H', 'F', 12], ['G', 'H', 2],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    ['H', 'E', 10],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `usort($edges, fn($a, $b) => $a[2] <=> $b[2]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `$parents = array_combine(str_split('ABCDEFGH'), str_split('ABCDEFGH'));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `function findRoot(array &$parents, string $vertex): string` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    while ($parents[$vertex] !== $vertex) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        $parents[$vertex] = $parents[$parents[$vertex]];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        $vertex = $parents[$vertex];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    return $vertex;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `$accepted = $skipped = $total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `foreach ($edges as [$a, $b, $weight]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    $first = findRoot($parents, $a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    $second = findRoot($parents, $b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    if ($first === $second) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        $skipped++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        $parents[$second] = $first;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        $accepted++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        if ($accepted === 7) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **515 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 508 tokens. The contiguous original span L3–L34 costs 596 tokens; the complete original source costs 640 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 508 tokens; removes `$edges = [` from the dependency chain described above.
- Without L4: 423 tokens; removes `['A', 'B', 7], ['C', 'A', 4], ['B', 'C', 9], ['B', 'D', 14], ['D', 'C', 6], ['C', 'E', 3],` from the dependency chain described above.
- Without L5: 421 tokens; removes `['E', 'D', 5], ['F', 'D', 11], ['E', 'G', 16], ['G', 'F', 8], ['H', 'F', 12], ['G', 'H', 2],` from the dependency chain described above.
- Without L6: 498 tokens; removes `['H', 'E', 10],` from the dependency chain described above.
- Without L8: 481 tokens; removes `usort($edges, fn($a, $b) => $a[2] <=> $b[2]);` from the dependency chain described above.
- Without L9: 485 tokens; removes `$parents = array_combine(str_split('ABCDEFGH'), str_split('ABCDEFGH'));` from the dependency chain described above.
- Without L11: 494 tokens; removes `function findRoot(array &$parents, string $vertex): string` from the dependency chain described above.
- Without L12: 513 tokens; removes `{` from the dependency chain described above.
- Without L13: 496 tokens; removes `while ($parents[$vertex] !== $vertex) {` from the dependency chain described above.
- Without L14: 493 tokens; removes `$parents[$vertex] = $parents[$parents[$vertex]];` from the dependency chain described above.
- Without L15: 500 tokens; removes `$vertex = $parents[$vertex];` from the dependency chain described above.
- Without L16: 512 tokens; removes `}` from the dependency chain described above.
- Without L17: 508 tokens; removes `return $vertex;` from the dependency chain described above.
- Without L18: 513 tokens; removes `}` from the dependency chain described above.
- Without L20: 497 tokens; removes `$accepted = $skipped = $total = 0;` from the dependency chain described above.
- Without L21: 491 tokens; removes `foreach ($edges as [$a, $b, $weight]) {` from the dependency chain described above.
- Without L22: 497 tokens; removes `$first = findRoot($parents, $a);` from the dependency chain described above.
- Without L23: 497 tokens; removes `$second = findRoot($parents, $b);` from the dependency chain described above.
- Without L24: 500 tokens; removes `if ($first === $second) {` from the dependency chain described above.
- Without L25: 508 tokens; removes `$skipped++;` from the dependency chain described above.
- Without L26: 508 tokens; removes `} else {` from the dependency chain described above.
- Without L27: 500 tokens; removes `$parents[$second] = $first;` from the dependency chain described above.
- Without L28: 508 tokens; removes `$accepted++;` from the dependency chain described above.
- Without L33: 500 tokens; removes `if ($accepted === 7) {` from the dependency chain described above.
- Without L34: 509 tokens; removes `break;` from the dependency chain described above.
