# Task B selection: 86_convex_hull / Ruby

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.rb`. Selected original locations: L1,L2,L3,L4,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L17,L19,L20.

- L1: `points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  [3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  [5, 6], [-6, -2], [2, -2], [7, -1], [-3, 4], [2, 8], [-6, 3]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `def cross(o, a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `def chain(ordered)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  result = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  ordered.each do |point|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    result.pop while result.length >= 2 && cross(result[-2], result[-1], point) <= 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    result << point` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `  result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `ordered = points.sort` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `hull = chain(ordered)[0...-1] + chain(ordered.reverse)[0...-1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **336 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 327 tokens. The contiguous original span L1–L20 costs 339 tokens; the complete original source costs 483 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 330 tokens; removes `points = [` from the dependency chain described above.
- Without L2: 266 tokens; removes `[3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1],` from the dependency chain described above.
- Without L3: 274 tokens; removes `[5, 6], [-6, -2], [2, -2], [7, -1], [-3, 4], [2, 8], [-6, 3]` from the dependency chain described above.
- Without L4: 334 tokens; removes `]` from the dependency chain described above.
- Without L6: 323 tokens; removes `def cross(o, a, b)` from the dependency chain described above.
- Without L7: 273 tokens; removes `(a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` from the dependency chain described above.
- Without L8: 334 tokens; removes `end` from the dependency chain described above.
- Without L10: 329 tokens; removes `def chain(ordered)` from the dependency chain described above.
- Without L11: 329 tokens; removes `result = []` from the dependency chain described above.
- Without L12: 325 tokens; removes `ordered.each do |point|` from the dependency chain described above.
- Without L13: 296 tokens; removes `result.pop while result.length >= 2 && cross(result[-2], result[-1], point) <= 0` from the dependency chain described above.
- Without L14: 329 tokens; removes `result << point` from the dependency chain described above.
- Without L15: 333 tokens; removes `end` from the dependency chain described above.
- Without L16: 333 tokens; removes `result` from the dependency chain described above.
- Without L17: 334 tokens; removes `end` from the dependency chain described above.
- Without L19: 328 tokens; removes `ordered = points.sort` from the dependency chain described above.
- Without L20: 306 tokens; removes `hull = chain(ordered)[0...-1] + chain(ordered.reverse)[0...-1]` from the dependency chain described above.
