# Task B selection: 86_convex_hull / Swift

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.swift`. Selected original locations: L3,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L20,L21,L22,L23,L24,L25,L26,L27,L28.

- L3: `typealias Point = (x: Int, y: Int)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `func cross(_ o: Point, _ a: Point, _ b: Point) -> Int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `func chain(_ points: [Point]) -> [Point] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    var result = [Point]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    for point in points {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        while result.count >= 2 && cross(result[result.count - 2], result.last!, point) <= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            result.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `        result.append(point)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `let input: [Point] = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    (3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6), (-6, -2), (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    (7, -1), (-3, 4), (2, 8), (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `var lower = chain(points), upper = chain(Array(points.reversed()))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `lower.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `upper.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `lower.append(contentsOf: upper)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **483 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 452 tokens. The contiguous original span L3–L28 costs 486 tokens; the complete original source costs 663 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 465 tokens; removes `typealias Point = (x: Int, y: Int)` from the dependency chain described above.
- Without L5: 452 tokens; removes `func cross(_ o: Point, _ a: Point, _ b: Point) -> Int {` from the dependency chain described above.
- Without L6: 428 tokens; removes `(a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)` from the dependency chain described above.
- Without L7: 481 tokens; removes `}` from the dependency chain described above.
- Without L9: 461 tokens; removes `func chain(_ points: [Point]) -> [Point] {` from the dependency chain described above.
- Without L10: 470 tokens; removes `var result = [Point]()` from the dependency chain described above.
- Without L11: 472 tokens; removes `for point in points {` from the dependency chain described above.
- Without L12: 440 tokens; removes `while result.count >= 2 && cross(result[result.count - 2], result.last!, point) <= 0 {` from the dependency chain described above.
- Without L13: 473 tokens; removes `result.removeLast()` from the dependency chain described above.
- Without L14: 479 tokens; removes `}` from the dependency chain described above.
- Without L15: 474 tokens; removes `result.append(point)` from the dependency chain described above.
- Without L16: 480 tokens; removes `}` from the dependency chain described above.
- Without L17: 478 tokens; removes `return result` from the dependency chain described above.
- Without L18: 481 tokens; removes `}` from the dependency chain described above.
- Without L20: 470 tokens; removes `let input: [Point] = [` from the dependency chain described above.
- Without L21: 386 tokens; removes `(3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6), (-6, -2), (2, -2),` from the dependency chain described above.
- Without L22: 447 tokens; removes `(7, -1), (-3, 4), (2, 8), (-6, 3),` from the dependency chain described above.
- Without L23: 481 tokens; removes `]` from the dependency chain described above.
- Without L24: 429 tokens; removes `let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }` from the dependency chain described above.
- Without L25: 455 tokens; removes `var lower = chain(points), upper = chain(Array(points.reversed()))` from the dependency chain described above.
- Without L26: 476 tokens; removes `lower.removeLast()` from the dependency chain described above.
- Without L27: 476 tokens; removes `upper.removeLast()` from the dependency chain described above.
- Without L28: 472 tokens; removes `lower.append(contentsOf: upper)` from the dependency chain described above.
