# Task B selection: 86_convex_hull / Dart

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.dart`. Selected original locations: L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L37,L38,L39.

- L2: `  final points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    (3, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    (-6, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    (8, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (0, 0),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    (-3, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    (4, -3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    (1, -5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    (-2, 1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    (5, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    (-6, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    (7, -1),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    (-3, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    (2, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `  points.sort((a, b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    final c = a.$1.compareTo(b.$1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    return c != 0 ? c : a.$2.compareTo(b.$2);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  int cross((int, int) o, (int, int) a, (int, int) b) =>` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  List<(int, int)> chain(Iterable<(int, int)> source) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    final result = <(int, int)>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    for (final p in source) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `      while (result.length >= 2 &&` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `          cross(result[result.length - 2], result.last, p) <= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        result.removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `      result.add(p);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `    return result;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `  final lower = chain(points)..removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `  final upper = chain(points.reversed)..removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `  final hull = [...lower, ...upper];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **519 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 500 tokens. The contiguous original span L2–L39 costs 520 tokens; the complete original source costs 706 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 510 tokens; removes `final points = [` from the dependency chain described above.
- Without L3: 510 tokens; removes `(3, 2),` from the dependency chain described above.
- Without L4: 509 tokens; removes `(-6, 1),` from the dependency chain described above.
- Without L5: 510 tokens; removes `(8, 4),` from the dependency chain described above.
- Without L6: 510 tokens; removes `(0, 0),` from the dependency chain described above.
- Without L7: 509 tokens; removes `(-3, 7),` from the dependency chain described above.
- Without L8: 509 tokens; removes `(4, -3),` from the dependency chain described above.
- Without L9: 509 tokens; removes `(1, -5),` from the dependency chain described above.
- Without L10: 509 tokens; removes `(-2, 1),` from the dependency chain described above.
- Without L11: 510 tokens; removes `(5, 6),` from the dependency chain described above.
- Without L12: 508 tokens; removes `(-6, -2),` from the dependency chain described above.
- Without L13: 509 tokens; removes `(2, -2),` from the dependency chain described above.
- Without L14: 509 tokens; removes `(7, -1),` from the dependency chain described above.
- Without L15: 509 tokens; removes `(-3, 4),` from the dependency chain described above.
- Without L16: 510 tokens; removes `(2, 8),` from the dependency chain described above.
- Without L17: 509 tokens; removes `(-6, 3),` from the dependency chain described above.
- Without L18: 515 tokens; removes `];` from the dependency chain described above.
- Without L19: 505 tokens; removes `points.sort((a, b) {` from the dependency chain described above.
- Without L20: 499 tokens; removes `final c = a.$1.compareTo(b.$1);` from the dependency chain described above.
- Without L21: 491 tokens; removes `return c != 0 ? c : a.$2.compareTo(b.$2);` from the dependency chain described above.
- Without L22: 514 tokens; removes `});` from the dependency chain described above.
- Without L23: 482 tokens; removes `int cross((int, int) o, (int, int) a, (int, int) b) =>` from the dependency chain described above.
- Without L24: 462 tokens; removes `(a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);` from the dependency chain described above.
- Without L25: 491 tokens; removes `List<(int, int)> chain(Iterable<(int, int)> source) {` from the dependency chain described above.
- Without L26: 501 tokens; removes `final result = <(int, int)>[];` from the dependency chain described above.
- Without L27: 504 tokens; removes `for (final p in source) {` from the dependency chain described above.
- Without L28: 504 tokens; removes `while (result.length >= 2 &&` from the dependency chain described above.
- Without L29: 487 tokens; removes `cross(result[result.length - 2], result.last, p) <= 0) {` from the dependency chain described above.
- Without L30: 509 tokens; removes `result.removeLast();` from the dependency chain described above.
- Without L31: 515 tokens; removes `}` from the dependency chain described above.
- Without L32: 509 tokens; removes `result.add(p);` from the dependency chain described above.
- Without L33: 516 tokens; removes `}` from the dependency chain described above.
- Without L34: 513 tokens; removes `return result;` from the dependency chain described above.
- Without L35: 516 tokens; removes `}` from the dependency chain described above.
- Without L37: 501 tokens; removes `final lower = chain(points)..removeLast();` from the dependency chain described above.
- Without L38: 499 tokens; removes `final upper = chain(points.reversed)..removeLast();` from the dependency chain described above.
- Without L39: 502 tokens; removes `final hull = [...lower, ...upper];` from the dependency chain described above.
