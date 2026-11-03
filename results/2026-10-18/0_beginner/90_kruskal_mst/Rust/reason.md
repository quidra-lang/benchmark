# Task B selection: 90_kruskal_mst / Rust

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.rs`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L20,L22,L23,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39.

- L1: `fn find(parent: &mut [usize], v: usize) -> usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    if parent[v] != v {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        let next = parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        parent[v] = find(parent, next);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `    parent[v]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    let mut edges = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        ('A', 'B', 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        ('C', 'A', 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        ('B', 'C', 9),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        ('B', 'D', 14),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        ('D', 'C', 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        ('C', 'E', 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        ('E', 'D', 5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        ('G', 'F', 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        ('G', 'H', 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        ('H', 'E', 10),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    edges.sort_by_key(|e| e.2);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    let mut parent: Vec<usize> = (0..8).collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    let (mut accepted, mut total, mut skipped) = (0, 0, 0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    for (a, b, w) in edges {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if accepted == 7 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `        let ra = find(&mut parent, a as usize - 'A' as usize);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        let rb = find(&mut parent, b as usize - 'A' as usize);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        if ra == rb {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            skipped += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `        parent[ra] = rb;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        accepted += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **504 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 480 tokens. The contiguous original span L1–L39 costs 571 tokens; the complete original source costs 650 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 478 tokens; removes `fn find(parent: &mut [usize], v: usize) -> usize {` from the dependency chain described above.
- Without L2: 490 tokens; removes `if parent[v] != v {` from the dependency chain described above.
- Without L3: 490 tokens; removes `let next = parent[v];` from the dependency chain described above.
- Without L4: 486 tokens; removes `parent[v] = find(parent, next);` from the dependency chain described above.
- Without L5: 501 tokens; removes `}` from the dependency chain described above.
- Without L6: 498 tokens; removes `parent[v]` from the dependency chain described above.
- Without L7: 502 tokens; removes `}` from the dependency chain described above.
- Without L10: 493 tokens; removes `let mut edges = [` from the dependency chain described above.
- Without L11: 487 tokens; removes `('A', 'B', 7),` from the dependency chain described above.
- Without L12: 487 tokens; removes `('C', 'A', 4),` from the dependency chain described above.
- Without L13: 487 tokens; removes `('B', 'C', 9),` from the dependency chain described above.
- Without L14: 486 tokens; removes `('B', 'D', 14),` from the dependency chain described above.
- Without L15: 487 tokens; removes `('D', 'C', 6),` from the dependency chain described above.
- Without L16: 487 tokens; removes `('C', 'E', 3),` from the dependency chain described above.
- Without L17: 487 tokens; removes `('E', 'D', 5),` from the dependency chain described above.
- Without L20: 487 tokens; removes `('G', 'F', 8),` from the dependency chain described above.
- Without L22: 487 tokens; removes `('G', 'H', 2),` from the dependency chain described above.
- Without L23: 486 tokens; removes `('H', 'E', 10),` from the dependency chain described above.
- Without L25: 486 tokens; removes `edges.sort_by_key(|e| e.2);` from the dependency chain described above.
- Without L26: 478 tokens; removes `let mut parent: Vec<usize> = (0..8).collect();` from the dependency chain described above.
- Without L27: 472 tokens; removes `let (mut accepted, mut total, mut skipped) = (0, 0, 0);` from the dependency chain described above.
- Without L28: 485 tokens; removes `for (a, b, w) in edges {` from the dependency chain described above.
- Without L29: 492 tokens; removes `if accepted == 7 {` from the dependency chain described above.
- Without L30: 498 tokens; removes `break;` from the dependency chain described above.
- Without L31: 500 tokens; removes `}` from the dependency chain described above.
- Without L32: 470 tokens; removes `let ra = find(&mut parent, a as usize - 'A' as usize);` from the dependency chain described above.
- Without L33: 470 tokens; removes `let rb = find(&mut parent, b as usize - 'A' as usize);` from the dependency chain described above.
- Without L34: 492 tokens; removes `if ra == rb {` from the dependency chain described above.
- Without L35: 494 tokens; removes `skipped += 1;` from the dependency chain described above.
- Without L36: 498 tokens; removes `continue;` from the dependency chain described above.
- Without L37: 500 tokens; removes `}` from the dependency chain described above.
- Without L38: 492 tokens; removes `parent[ra] = rb;` from the dependency chain described above.
- Without L39: 495 tokens; removes `accepted += 1;` from the dependency chain described above.
