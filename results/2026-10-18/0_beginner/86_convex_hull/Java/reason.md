# Task B selection: 86_convex_hull / Java

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `Main.java`. Selected original locations: L7,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L7: `    record Point(int x, int y) {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    static int cross(Point o, Point a, Point b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        return (a.x() - o.x()) * (b.y() - o.y()) - (a.y() - o.y()) * (b.x() - o.x());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    static List<Point> chain(List<Point> points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        List<Point> result = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        for (Point point : points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            while (result.size() >= 2 && cross(result.get(result.size() - 2), result.getLast(), point) <= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `                result.removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `            result.add(point);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `        return result;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `        List<Point> points = new ArrayList<>(List.of(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `                new Point(3, 2), new Point(-6, 1), new Point(8, 4), new Point(0, 0), new Point(-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `                new Point(4, -3), new Point(1, -5), new Point(-2, 1), new Point(5, 6), new Point(-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `                new Point(2, -2), new Point(7, -1), new Point(-3, 4), new Point(2, 8), new Point(-6, 3)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        points.sort(Comparator.comparingInt(Point::x).thenComparingInt(Point::y));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        List<Point> lower = chain(points);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        List<Point> upper = chain(points.reversed());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        lower.removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        upper.removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        lower.addAll(upper);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **582 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 549 tokens. The contiguous original span L7–L34 costs 602 tokens; the complete original source costs 890 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 564 tokens; removes `record Point(int x, int y) {}` from the dependency chain described above.
- Without L9: 558 tokens; removes `static int cross(Point o, Point a, Point b) {` from the dependency chain described above.
- Without L10: 507 tokens; removes `return (a.x() - o.x()) * (b.y() - o.y()) - (a.y() - o.y()) * (b.x() - o.x());` from the dependency chain described above.
- Without L11: 579 tokens; removes `}` from the dependency chain described above.
- Without L13: 562 tokens; removes `static List<Point> chain(List<Point> points) {` from the dependency chain described above.
- Without L14: 561 tokens; removes `List<Point> result = new ArrayList<>();` from the dependency chain described above.
- Without L15: 566 tokens; removes `for (Point point : points) {` from the dependency chain described above.
- Without L16: 528 tokens; removes `while (result.size() >= 2 && cross(result.get(result.size() - 2), result.getLast(), point) <= 0) {` from the dependency chain described above.
- Without L17: 570 tokens; removes `result.removeLast();` from the dependency chain described above.
- Without L18: 577 tokens; removes `}` from the dependency chain described above.
- Without L19: 571 tokens; removes `result.add(point);` from the dependency chain described above.
- Without L20: 578 tokens; removes `}` from the dependency chain described above.
- Without L21: 575 tokens; removes `return result;` from the dependency chain described above.
- Without L22: 579 tokens; removes `}` from the dependency chain described above.
- Without L25: 559 tokens; removes `List<Point> points = new ArrayList<>(List.of(` from the dependency chain described above.
- Without L26: 521 tokens; removes `new Point(3, 2), new Point(-6, 1), new Point(8, 4), new Point(0, 0), new Point(-3, 7),` from the dependency chain described above.
- Without L27: 518 tokens; removes `new Point(4, -3), new Point(1, -5), new Point(-2, 1), new Point(5, 6), new Point(-6, -2),` from the dependency chain described above.
- Without L28: 517 tokens; removes `new Point(2, -2), new Point(7, -1), new Point(-3, 4), new Point(2, 8), new Point(-6, 3)));` from the dependency chain described above.
- Without L29: 555 tokens; removes `points.sort(Comparator.comparingInt(Point::x).thenComparingInt(Point::y));` from the dependency chain described above.
- Without L30: 565 tokens; removes `List<Point> lower = chain(points);` from the dependency chain described above.
- Without L31: 561 tokens; removes `List<Point> upper = chain(points.reversed());` from the dependency chain described above.
- Without L32: 572 tokens; removes `lower.removeLast();` from the dependency chain described above.
- Without L33: 572 tokens; removes `upper.removeLast();` from the dependency chain described above.
- Without L34: 571 tokens; removes `lower.addAll(upper);` from the dependency chain described above.
