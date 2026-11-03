# Task B selection: 86_convex_hull / Kotlin

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.kt`. Selected original locations: L3,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29.

- L3: `data class Point(val x: Int, val y: Int)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `fun cross(o: Point, a: Point, b: Point): Int =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `fun chain(points: List<Point>): MutableList<Point> {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    val result = mutableListOf<Point>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    for (point in points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        while (result.size >= 2 && cross(result[result.size - 2], result.last(), point) <= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            result.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `        result.add(point)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `    val points = listOf(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        Point(3, 2), Point(-6, 1), Point(8, 4), Point(0, 0), Point(-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        Point(4, -3), Point(1, -5), Point(-2, 1), Point(5, 6), Point(-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        Point(2, -2), Point(7, -1), Point(-3, 4), Point(2, 8), Point(-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    ).sortedWith(compareBy<Point> { it.x }.thenBy { it.y })` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    val lower = chain(points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    val upper = chain(points.reversed())` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    lower.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    upper.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    lower.addAll(upper)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **477 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 447 tokens. The contiguous original span L3–L29 costs 488 tokens; the complete original source costs 666 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 456 tokens; removes `data class Point(val x: Int, val y: Int)` from the dependency chain described above.
- Without L5: 453 tokens; removes `fun cross(o: Point, a: Point, b: Point): Int =` from the dependency chain described above.
- Without L6: 422 tokens; removes `(a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)` from the dependency chain described above.
- Without L8: 455 tokens; removes `fun chain(points: List<Point>): MutableList<Point> {` from the dependency chain described above.
- Without L9: 461 tokens; removes `val result = mutableListOf<Point>()` from the dependency chain described above.
- Without L10: 464 tokens; removes `for (point in points) {` from the dependency chain described above.
- Without L11: 431 tokens; removes `while (result.size >= 2 && cross(result[result.size - 2], result.last(), point) <= 0) {` from the dependency chain described above.
- Without L12: 467 tokens; removes `result.removeLast()` from the dependency chain described above.
- Without L13: 473 tokens; removes `}` from the dependency chain described above.
- Without L14: 468 tokens; removes `result.add(point)` from the dependency chain described above.
- Without L15: 474 tokens; removes `}` from the dependency chain described above.
- Without L16: 472 tokens; removes `return result` from the dependency chain described above.
- Without L17: 475 tokens; removes `}` from the dependency chain described above.
- Without L20: 466 tokens; removes `val points = listOf(` from the dependency chain described above.
- Without L21: 428 tokens; removes `Point(3, 2), Point(-6, 1), Point(8, 4), Point(0, 0), Point(-3, 7),` from the dependency chain described above.
- Without L22: 425 tokens; removes `Point(4, -3), Point(1, -5), Point(-2, 1), Point(5, 6), Point(-6, -2),` from the dependency chain described above.
- Without L23: 426 tokens; removes `Point(2, -2), Point(7, -1), Point(-3, 4), Point(2, 8), Point(-6, 3),` from the dependency chain described above.
- Without L24: 446 tokens; removes `).sortedWith(compareBy<Point> { it.x }.thenBy { it.y })` from the dependency chain described above.
- Without L25: 465 tokens; removes `val lower = chain(points)` from the dependency chain described above.
- Without L26: 461 tokens; removes `val upper = chain(points.reversed())` from the dependency chain described above.
- Without L27: 469 tokens; removes `lower.removeLast()` from the dependency chain described above.
- Without L28: 469 tokens; removes `upper.removeLast()` from the dependency chain described above.
- Without L29: 468 tokens; removes `lower.addAll(upper)` from the dependency chain described above.
