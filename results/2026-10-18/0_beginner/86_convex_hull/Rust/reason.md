# Task B selection: 86_convex_hull / Rust

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.rs`. Selected original locations: L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40.

- L1: `fn cross(o: (i32, i32), a: (i32, i32), b: (i32, i32)) -> i32 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `    let mut points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        (3, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        (-6, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        (8, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        (0, 0),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        (-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        (4, -3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        (1, -5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        (-2, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        (5, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        (-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        (7, -1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        (-3, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        (2, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    points.sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    let mut lower = Vec::new();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    let mut upper = Vec::new();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    for &p in &points {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            lower.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `        lower.push(p);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    for &p in points.iter().rev() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            upper.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `        upper.push(p);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `    lower.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    upper.pop();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    lower.extend(upper);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **527 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 507 tokens. The contiguous original span L1–L40 costs 536 tokens; the complete original source costs 724 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 487 tokens; removes `fn cross(o: (i32, i32), a: (i32, i32), b: (i32, i32)) -> i32 {` from the dependency chain described above.
- Without L2: 480 tokens; removes `(a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)` from the dependency chain described above.
- Without L3: 525 tokens; removes `}` from the dependency chain described above.
- Without L6: 516 tokens; removes `let mut points = [` from the dependency chain described above.
- Without L7: 517 tokens; removes `(3, 2),` from the dependency chain described above.
- Without L8: 516 tokens; removes `(-6, 1),` from the dependency chain described above.
- Without L9: 517 tokens; removes `(8, 4),` from the dependency chain described above.
- Without L10: 517 tokens; removes `(0, 0),` from the dependency chain described above.
- Without L11: 516 tokens; removes `(-3, 7),` from the dependency chain described above.
- Without L12: 516 tokens; removes `(4, -3),` from the dependency chain described above.
- Without L13: 516 tokens; removes `(1, -5),` from the dependency chain described above.
- Without L14: 516 tokens; removes `(-2, 1),` from the dependency chain described above.
- Without L15: 517 tokens; removes `(5, 6),` from the dependency chain described above.
- Without L16: 515 tokens; removes `(-6, -2),` from the dependency chain described above.
- Without L17: 516 tokens; removes `(2, -2),` from the dependency chain described above.
- Without L18: 516 tokens; removes `(7, -1),` from the dependency chain described above.
- Without L19: 516 tokens; removes `(-3, 4),` from the dependency chain described above.
- Without L20: 517 tokens; removes `(2, 8),` from the dependency chain described above.
- Without L21: 516 tokens; removes `(-6, 3),` from the dependency chain described above.
- Without L22: 523 tokens; removes `];` from the dependency chain described above.
- Without L23: 519 tokens; removes `points.sort();` from the dependency chain described above.
- Without L24: 511 tokens; removes `let mut lower = Vec::new();` from the dependency chain described above.
- Without L25: 511 tokens; removes `let mut upper = Vec::new();` from the dependency chain described above.
- Without L26: 514 tokens; removes `for &p in &points {` from the dependency chain described above.
- Without L27: 472 tokens; removes `while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0 {` from the dependency chain described above.
- Without L28: 517 tokens; removes `lower.pop();` from the dependency chain described above.
- Without L29: 523 tokens; removes `}` from the dependency chain described above.
- Without L30: 517 tokens; removes `lower.push(p);` from the dependency chain described above.
- Without L31: 524 tokens; removes `}` from the dependency chain described above.
- Without L32: 507 tokens; removes `for &p in points.iter().rev() {` from the dependency chain described above.
- Without L33: 472 tokens; removes `while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0 {` from the dependency chain described above.
- Without L34: 517 tokens; removes `upper.pop();` from the dependency chain described above.
- Without L35: 523 tokens; removes `}` from the dependency chain described above.
- Without L36: 517 tokens; removes `upper.push(p);` from the dependency chain described above.
- Without L37: 524 tokens; removes `}` from the dependency chain described above.
- Without L38: 519 tokens; removes `lower.pop();` from the dependency chain described above.
- Without L39: 519 tokens; removes `upper.pop();` from the dependency chain described above.
- Without L40: 518 tokens; removes `lower.extend(upper);` from the dependency chain described above.
