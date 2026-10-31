# Task B selection: 86_convex_hull / C++

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.cpp`. Selected original locations: L6,L8,L9,L10,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30.

- L6: `using Point = std::pair<int, int>;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `int cross(Point o, Point a, Point b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    return (a.first - o.first) * (b.second - o.second) - (a.second - o.second) * (b.first - o.first);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    std::vector<Point> points = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        {5, 6}, {-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    std::sort(points.begin(), points.end());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    std::vector<Point> lower, upper;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    for (Point p : points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        while (lower.size() >= 2 && cross(lower[lower.size() - 2], lower.back(), p) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            lower.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        lower.push_back(p);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    for (auto i = points.rbegin(); i != points.rend(); ++i) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        Point p = *i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        while (upper.size() >= 2 && cross(upper[upper.size() - 2], upper.back(), p) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            upper.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        upper.push_back(p);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    lower.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    upper.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    lower.insert(lower.end(), upper.begin(), upper.end());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **537 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 529 tokens. The contiguous original span L6–L30 costs 547 tokens; the complete original source costs 810 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 520 tokens; removes `using Point = std::pair<int, int>;` from the dependency chain described above.
- Without L8: 516 tokens; removes `int cross(Point o, Point a, Point b) {` from the dependency chain described above.
- Without L9: 479 tokens; removes `return (a.first - o.first) * (b.second - o.second) - (a.second - o.second) * (b.first - o.first);` from the dependency chain described above.
- Without L10: 535 tokens; removes `}` from the dependency chain described above.
- Without L13: 455 tokens; removes `std::vector<Point> points = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1},` from the dependency chain described above.
- Without L14: 472 tokens; removes `{5, 6}, {-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};` from the dependency chain described above.
- Without L15: 517 tokens; removes `std::sort(points.begin(), points.end());` from the dependency chain described above.
- Without L16: 523 tokens; removes `std::vector<Point> lower, upper;` from the dependency chain described above.
- Without L17: 522 tokens; removes `for (Point p : points) {` from the dependency chain described above.
- Without L18: 489 tokens; removes `while (lower.size() >= 2 && cross(lower[lower.size() - 2], lower.back(), p) <= 0)` from the dependency chain described above.
- Without L19: 525 tokens; removes `lower.pop_back();` from the dependency chain described above.
- Without L20: 525 tokens; removes `lower.push_back(p);` from the dependency chain described above.
- Without L21: 534 tokens; removes `}` from the dependency chain described above.
- Without L22: 503 tokens; removes `for (auto i = points.rbegin(); i != points.rend(); ++i) {` from the dependency chain described above.
- Without L23: 525 tokens; removes `Point p = *i;` from the dependency chain described above.
- Without L24: 489 tokens; removes `while (upper.size() >= 2 && cross(upper[upper.size() - 2], upper.back(), p) <= 0)` from the dependency chain described above.
- Without L25: 525 tokens; removes `upper.pop_back();` from the dependency chain described above.
- Without L26: 525 tokens; removes `upper.push_back(p);` from the dependency chain described above.
- Without L27: 534 tokens; removes `}` from the dependency chain described above.
- Without L28: 527 tokens; removes `lower.pop_back();` from the dependency chain described above.
- Without L29: 527 tokens; removes `upper.pop_back();` from the dependency chain described above.
- Without L30: 510 tokens; removes `lower.insert(lower.end(), upper.begin(), upper.end());` from the dependency chain described above.
