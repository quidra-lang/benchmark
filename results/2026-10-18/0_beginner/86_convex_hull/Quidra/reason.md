# Task B selection: 86_convex_hull / Quidra

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.qui`. Selected original locations: L1,L2,L4,L5,L6,L7,L8,L9,L10,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27.

- L1: `int cross(int[] o, int[] a, int[] b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `int[][] chain(int[][] points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    int[][] result = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    for int[] point = points[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        while len(result) >= 2 and cross(result[len(result) - 2], result[len(result) - 1], point) <= 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `            result = result[:<len(result) - 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        result = result.append(point)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `int[][] points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    [3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1], [5, 6], [-6, -2], [2, -2],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    [7, -1], [-3, 4], [2, 8], [-6, 3],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `for 1 <= int i < int(len(points))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    int[] value = points[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    int j = i - 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    while j >= 0 and (points[j][0] > value[0] or (points[j][0] == value[0] and points[j][1] > value[1]))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        points[j + 1] = points[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        j -= 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    points[j + 1] = value` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `int[][] lower = chain(points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `int[][] upper = chain(points[::-1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `lower = lower[:<len(lower) - 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `upper = upper[:<len(upper) - 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `int[][] hull = lower.concat(upper)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **587 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 585 tokens. The contiguous original span L1–L27 costs 589 tokens; the complete original source costs 769 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 565 tokens; removes `int cross(int[] o, int[] a, int[] b)` from the dependency chain described above.
- Without L2: 522 tokens; removes `return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])` from the dependency chain described above.
- Without L4: 574 tokens; removes `int[][] chain(int[][] points)` from the dependency chain described above.
- Without L5: 576 tokens; removes `int[][] result = []` from the dependency chain described above.
- Without L6: 574 tokens; removes `for int[] point = points[]` from the dependency chain described above.
- Without L7: 537 tokens; removes `while len(result) >= 2 and cross(result[len(result) - 2], result[len(result) - 1], point) <= 0` from the dependency chain described above.
- Without L8: 567 tokens; removes `result = result[:<len(result) - 1]` from the dependency chain described above.
- Without L9: 574 tokens; removes `result = result.append(point)` from the dependency chain described above.
- Without L10: 582 tokens; removes `return result` from the dependency chain described above.
- Without L12: 577 tokens; removes `int[][] points = [` from the dependency chain described above.
- Without L13: 490 tokens; removes `[3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1], [5, 6], [-6, -2], [2, -2],` from the dependency chain described above.
- Without L14: 551 tokens; removes `[7, -1], [-3, 4], [2, 8], [-6, 3],` from the dependency chain described above.
- Without L15: 585 tokens; removes `]` from the dependency chain described above.
- Without L16: 567 tokens; removes `for 1 <= int i < int(len(points))` from the dependency chain described above.
- Without L17: 574 tokens; removes `int[] value = points[i]` from the dependency chain described above.
- Without L18: 574 tokens; removes `int j = i - 1` from the dependency chain described above.
- Without L19: 523 tokens; removes `while j >= 0 and (points[j][0] > value[0] or (points[j][0] == value[0] and points[j][1] > value[1]))` from the dependency chain described above.
- Without L20: 569 tokens; removes `points[j + 1] = points[j]` from the dependency chain described above.
- Without L21: 579 tokens; removes `j -= 1` from the dependency chain described above.
- Without L22: 573 tokens; removes `points[j + 1] = value` from the dependency chain described above.
- Without L23: 574 tokens; removes `int[][] lower = chain(points)` from the dependency chain described above.
- Without L24: 569 tokens; removes `int[][] upper = chain(points[::-1])` from the dependency chain described above.
- Without L25: 570 tokens; removes `lower = lower[:<len(lower) - 1]` from the dependency chain described above.
- Without L26: 570 tokens; removes `upper = upper[:<len(upper) - 1]` from the dependency chain described above.
- Without L27: 572 tokens; removes `int[][] hull = lower.concat(upper)` from the dependency chain described above.
