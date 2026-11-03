# Task B selection: 86_convex_hull / Python

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.py`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L20,L21,L24,L25,L26,L27,L28,L29,L30,L33,L34.

- L1: `points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    (3, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    (-6, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    (8, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    (0, 0),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    (4, -3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    (1, -5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    (-2, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    (5, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    (-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    (7, -1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    (-3, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    (2, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `def cross(o, a, b):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `def chain(ordered):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    result = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    for point in ordered:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        while len(result) >= 2 and cross(result[-2], result[-1], point) <= 0:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            result.pop()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        result.append(point)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `ordered = sorted(points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `hull = chain(ordered)[:-1] + chain(reversed(ordered))[:-1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **356 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 354 tokens. The contiguous original span L1–L34 costs 362 tokens; the complete original source costs 505 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 350 tokens; removes `points = [` from the dependency chain described above.
- Without L2: 347 tokens; removes `(3, 2),` from the dependency chain described above.
- Without L3: 346 tokens; removes `(-6, 1),` from the dependency chain described above.
- Without L4: 347 tokens; removes `(8, 4),` from the dependency chain described above.
- Without L5: 347 tokens; removes `(0, 0),` from the dependency chain described above.
- Without L6: 346 tokens; removes `(-3, 7),` from the dependency chain described above.
- Without L7: 346 tokens; removes `(4, -3),` from the dependency chain described above.
- Without L8: 346 tokens; removes `(1, -5),` from the dependency chain described above.
- Without L9: 346 tokens; removes `(-2, 1),` from the dependency chain described above.
- Without L10: 347 tokens; removes `(5, 6),` from the dependency chain described above.
- Without L11: 345 tokens; removes `(-6, -2),` from the dependency chain described above.
- Without L12: 346 tokens; removes `(2, -2),` from the dependency chain described above.
- Without L13: 346 tokens; removes `(7, -1),` from the dependency chain described above.
- Without L14: 346 tokens; removes `(-3, 4),` from the dependency chain described above.
- Without L15: 347 tokens; removes `(2, 8),` from the dependency chain described above.
- Without L16: 346 tokens; removes `(-6, 3),` from the dependency chain described above.
- Without L17: 354 tokens; removes `]` from the dependency chain described above.
- Without L20: 342 tokens; removes `def cross(o, a, b):` from the dependency chain described above.
- Without L21: 291 tokens; removes `return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` from the dependency chain described above.
- Without L24: 348 tokens; removes `def chain(ordered):` from the dependency chain described above.
- Without L25: 349 tokens; removes `result = []` from the dependency chain described above.
- Without L26: 346 tokens; removes `for point in ordered:` from the dependency chain described above.
- Without L27: 317 tokens; removes `while len(result) >= 2 and cross(result[-2], result[-1], point) <= 0:` from the dependency chain described above.
- Without L28: 347 tokens; removes `result.pop()` from the dependency chain described above.
- Without L29: 347 tokens; removes `result.append(point)` from the dependency chain described above.
- Without L30: 351 tokens; removes `return result` from the dependency chain described above.
- Without L33: 347 tokens; removes `ordered = sorted(points)` from the dependency chain described above.
- Without L34: 329 tokens; removes `hull = chain(ordered)[:-1] + chain(reversed(ordered))[:-1]` from the dependency chain described above.
