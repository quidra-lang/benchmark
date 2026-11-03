# Task B selection: 86_convex_hull / C

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.c`. Selected original locations: L4,L5,L6,L8,L9,L10,L11,L13,L14,L15,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36.

- L4: `typedef struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    int x, y;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `} Point;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `int compare(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    const Point *x = a, *y = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    return x->x != y->x ? x->x - y->x : x->y - y->y;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `int cross(Point o, Point a, Point b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    Point points[] = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        {-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    qsort(points, 15, sizeof(Point), compare);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    Point lower[15], upper[15], hull[30];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    int nl = 0, nu = 0, nh = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    for (int i = 0; i < 15; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        while (nl >= 2 && cross(lower[nl - 2], lower[nl - 1], points[i]) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            nl--;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        lower[nl++] = points[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    for (int i = 14; i >= 0; i--) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        while (nu >= 2 && cross(upper[nu - 2], upper[nu - 1], points[i]) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            nu--;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        upper[nu++] = points[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    for (int i = 0; i < nl - 1; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        hull[nh++] = lower[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for (int i = 0; i < nu - 1; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        hull[nh++] = upper[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **681 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 651 tokens. The contiguous original span L4–L36 costs 693 tokens; the complete original source costs 904 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L4: 675 tokens; removes `typedef struct {` from the dependency chain described above.
- Without L5: 672 tokens; removes `int x, y;` from the dependency chain described above.
- Without L6: 676 tokens; removes `} Point;` from the dependency chain described above.
- Without L8: 659 tokens; removes `int compare(const void *a, const void *b) {` from the dependency chain described above.
- Without L9: 660 tokens; removes `const Point *x = a, *y = b;` from the dependency chain described above.
- Without L10: 643 tokens; removes `return x->x != y->x ? x->x - y->x : x->y - y->y;` from the dependency chain described above.
- Without L11: 679 tokens; removes `}` from the dependency chain described above.
- Without L13: 660 tokens; removes `int cross(Point o, Point a, Point b) {` from the dependency chain described above.
- Without L14: 623 tokens; removes `return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);` from the dependency chain described above.
- Without L15: 679 tokens; removes `}` from the dependency chain described above.
- Without L18: 595 tokens; removes `Point points[] = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},` from the dependency chain described above.
- Without L19: 624 tokens; removes `{-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};` from the dependency chain described above.
- Without L20: 661 tokens; removes `qsort(points, 15, sizeof(Point), compare);` from the dependency chain described above.
- Without L21: 657 tokens; removes `Point lower[15], upper[15], hull[30];` from the dependency chain described above.
- Without L22: 657 tokens; removes `int nl = 0, nu = 0, nh = 0;` from the dependency chain described above.
- Without L23: 654 tokens; removes `for (int i = 0; i < 15; i++) {` from the dependency chain described above.
- Without L24: 635 tokens; removes `while (nl >= 2 && cross(lower[nl - 2], lower[nl - 1], points[i]) <= 0)` from the dependency chain described above.
- Without L25: 674 tokens; removes `nl--;` from the dependency chain described above.
- Without L26: 665 tokens; removes `lower[nl++] = points[i];` from the dependency chain described above.
- Without L27: 678 tokens; removes `}` from the dependency chain described above.
- Without L28: 654 tokens; removes `for (int i = 14; i >= 0; i--) {` from the dependency chain described above.
- Without L29: 635 tokens; removes `while (nu >= 2 && cross(upper[nu - 2], upper[nu - 1], points[i]) <= 0)` from the dependency chain described above.
- Without L30: 674 tokens; removes `nu--;` from the dependency chain described above.
- Without L31: 665 tokens; removes `upper[nu++] = points[i];` from the dependency chain described above.
- Without L32: 678 tokens; removes `}` from the dependency chain described above.
- Without L33: 653 tokens; removes `for (int i = 0; i < nl - 1; i++)` from the dependency chain described above.
- Without L34: 665 tokens; removes `hull[nh++] = lower[i];` from the dependency chain described above.
- Without L35: 653 tokens; removes `for (int i = 0; i < nu - 1; i++)` from the dependency chain described above.
- Without L36: 665 tokens; removes `hull[nh++] = upper[i];` from the dependency chain described above.
