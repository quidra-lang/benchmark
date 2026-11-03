# Task B selection: 86_convex_hull / Julia

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.jl`. Selected original locations: L3,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35.

- L3: `cross_product(o, a, b) = (a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `function chain(points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    result = Tuple{Int,Int}[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    for point in points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        while length(result) >= 2 && cross_product(result[end-1], result[end], point) <= 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `            pop!(result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `        push!(result, point)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    points = sort([` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        (3, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        (-6, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        (8, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        (0, 0),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        (-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        (4, -3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        (1, -5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        (-2, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        (5, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        (-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        (7, -1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        (-3, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        (2, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    ])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    lower, upper = chain(points), chain(reverse(points))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    hull = vcat(lower[1:(end-1)], upper[1:(end-1)])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **393 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 384 tokens. The contiguous original span L3–L35 costs 401 tokens; the complete original source costs 571 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 330 tokens; removes `cross_product(o, a, b) = (a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1])` from the dependency chain described above.
- Without L5: 386 tokens; removes `function chain(points)` from the dependency chain described above.
- Without L6: 380 tokens; removes `result = Tuple{Int,Int}[]` from the dependency chain described above.
- Without L7: 384 tokens; removes `for point in points` from the dependency chain described above.
- Without L8: 353 tokens; removes `while length(result) >= 2 && cross_product(result[end-1], result[end], point) <= 0` from the dependency chain described above.
- Without L9: 384 tokens; removes `pop!(result)` from the dependency chain described above.
- Without L10: 389 tokens; removes `end` from the dependency chain described above.
- Without L11: 382 tokens; removes `push!(result, point)` from the dependency chain described above.
- Without L12: 390 tokens; removes `end` from the dependency chain described above.
- Without L13: 388 tokens; removes `return result` from the dependency chain described above.
- Without L14: 391 tokens; removes `end` from the dependency chain described above.
- Without L17: 384 tokens; removes `points = sort([` from the dependency chain described above.
- Without L18: 383 tokens; removes `(3, 2),` from the dependency chain described above.
- Without L19: 382 tokens; removes `(-6, 1),` from the dependency chain described above.
- Without L20: 383 tokens; removes `(8, 4),` from the dependency chain described above.
- Without L21: 383 tokens; removes `(0, 0),` from the dependency chain described above.
- Without L22: 382 tokens; removes `(-3, 7),` from the dependency chain described above.
- Without L23: 382 tokens; removes `(4, -3),` from the dependency chain described above.
- Without L24: 382 tokens; removes `(1, -5),` from the dependency chain described above.
- Without L25: 382 tokens; removes `(-2, 1),` from the dependency chain described above.
- Without L26: 383 tokens; removes `(5, 6),` from the dependency chain described above.
- Without L27: 381 tokens; removes `(-6, -2),` from the dependency chain described above.
- Without L28: 382 tokens; removes `(2, -2),` from the dependency chain described above.
- Without L29: 382 tokens; removes `(7, -1),` from the dependency chain described above.
- Without L30: 382 tokens; removes `(-3, 4),` from the dependency chain described above.
- Without L31: 383 tokens; removes `(2, 8),` from the dependency chain described above.
- Without L32: 382 tokens; removes `(-6, 3),` from the dependency chain described above.
- Without L33: 389 tokens; removes `])` from the dependency chain described above.
- Without L34: 371 tokens; removes `lower, upper = chain(points), chain(reverse(points))` from the dependency chain described above.
- Without L35: 362 tokens; removes `hull = vcat(lower[1:(end-1)], upper[1:(end-1)])` from the dependency chain described above.
