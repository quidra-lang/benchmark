# Task B selection: 86_convex_hull / Lua

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.lua`. Selected original locations: L1,L2,L3,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27.

- L1: `local function cross(o, a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `local function chain(points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    local result = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    for _, point in ipairs(points) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        while #result >= 2 and cross(result[#result - 1], result[#result], point) <= 0 do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `            table.remove(result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `        result[#result + 1] = point` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `local points = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    {3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6}, {-6, -2}, {2, -2},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    {7, -1}, {-3, 4}, {2, 8}, {-6, 3},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `table.sort(points, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `local reversed = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `for i = #points, 1, -1 do reversed[#reversed + 1] = points[i] end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `local lower, upper = chain(points), chain(reversed)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `table.remove(lower)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `table.remove(upper)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `local hull = lower` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `table.move(upper, 1, #upper, #hull + 1, hull)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **518 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 505 tokens. The contiguous original span L1–L27 costs 520 tokens; the complete original source costs 700 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 503 tokens; removes `local function cross(o, a, b)` from the dependency chain described above.
- Without L2: 453 tokens; removes `return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])` from the dependency chain described above.
- Without L3: 516 tokens; removes `end` from the dependency chain described above.
- Without L5: 509 tokens; removes `local function chain(points)` from the dependency chain described above.
- Without L6: 508 tokens; removes `local result = {}` from the dependency chain described above.
- Without L7: 501 tokens; removes `for _, point in ipairs(points) do` from the dependency chain described above.
- Without L8: 476 tokens; removes `while #result >= 2 and cross(result[#result - 1], result[#result], point) <= 0 do` from the dependency chain described above.
- Without L9: 508 tokens; removes `table.remove(result)` from the dependency chain described above.
- Without L10: 514 tokens; removes `end` from the dependency chain described above.
- Without L11: 502 tokens; removes `result[#result + 1] = point` from the dependency chain described above.
- Without L12: 515 tokens; removes `end` from the dependency chain described above.
- Without L13: 513 tokens; removes `return result` from the dependency chain described above.
- Without L14: 516 tokens; removes `end` from the dependency chain described above.
- Without L16: 510 tokens; removes `local points = {` from the dependency chain described above.
- Without L17: 421 tokens; removes `{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6}, {-6, -2}, {2, -2},` from the dependency chain described above.
- Without L18: 482 tokens; removes `{7, -1}, {-3, 4}, {2, 8}, {-6, 3},` from the dependency chain described above.
- Without L19: 516 tokens; removes `}` from the dependency chain described above.
- Without L20: 456 tokens; removes `table.sort(points, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)` from the dependency chain described above.
- Without L21: 509 tokens; removes `local reversed = {}` from the dependency chain described above.
- Without L22: 481 tokens; removes `for i = #points, 1, -1 do reversed[#reversed + 1] = points[i] end` from the dependency chain described above.
- Without L23: 498 tokens; removes `local lower, upper = chain(points), chain(reversed)` from the dependency chain described above.
- Without L24: 511 tokens; removes `table.remove(lower)` from the dependency chain described above.
- Without L25: 511 tokens; removes `table.remove(upper)` from the dependency chain described above.
- Without L26: 510 tokens; removes `local hull = lower` from the dependency chain described above.
- Without L27: 493 tokens; removes `table.move(upper, 1, #upper, #hull + 1, hull)` from the dependency chain described above.
