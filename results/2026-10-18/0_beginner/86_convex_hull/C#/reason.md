# Task B selection: 86_convex_hull / C#

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `Program.cs`. Selected original locations: L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37.

- L8: `static int Cross((int x, int y) o, (int x, int y) a, (int x, int y) b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `static List<(int x, int y)> Chain(IEnumerable<(int x, int y)> points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    var result = new List<(int x, int y)>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    foreach (var point in points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `        while (result.Count >= 2 && Cross(result[^2], result[^1], point) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `            result.RemoveAt(result.Count - 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `        result.Add(point);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `    return result;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `(int x, int y)[] input =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    (3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6), (-6, -2), (2, -2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    (7, -1), (-3, 4), (2, 8), (-6, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `var points = input.OrderBy(p => p.x).ThenBy(p => p.y).ToList();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `var lower = Chain(points);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `var upper = Chain(points.AsEnumerable().Reverse());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `lower.RemoveAt(lower.Count - 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `upper.RemoveAt(upper.Count - 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `lower.AddRange(upper);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **540 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 497 tokens. The contiguous original span L8–L37 costs 542 tokens; the complete original source costs 766 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 492 tokens; removes `static int Cross((int x, int y) o, (int x, int y) a, (int x, int y) b)` from the dependency chain described above.
- Without L9: 538 tokens; removes `{` from the dependency chain described above.
- Without L10: 482 tokens; removes `return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);` from the dependency chain described above.
- Without L11: 538 tokens; removes `}` from the dependency chain described above.
- Without L13: 504 tokens; removes `static List<(int x, int y)> Chain(IEnumerable<(int x, int y)> points)` from the dependency chain described above.
- Without L14: 538 tokens; removes `{` from the dependency chain described above.
- Without L15: 514 tokens; removes `var result = new List<(int x, int y)>();` from the dependency chain described above.
- Without L16: 527 tokens; removes `foreach (var point in points)` from the dependency chain described above.
- Without L17: 537 tokens; removes `{` from the dependency chain described above.
- Without L18: 501 tokens; removes `while (result.Count >= 2 && Cross(result[^2], result[^1], point) <= 0)` from the dependency chain described above.
- Without L19: 536 tokens; removes `{` from the dependency chain described above.
- Without L20: 522 tokens; removes `result.RemoveAt(result.Count - 1);` from the dependency chain described above.
- Without L21: 536 tokens; removes `}` from the dependency chain described above.
- Without L22: 530 tokens; removes `result.Add(point);` from the dependency chain described above.
- Without L23: 537 tokens; removes `}` from the dependency chain described above.
- Without L24: 534 tokens; removes `return result;` from the dependency chain described above.
- Without L25: 538 tokens; removes `}` from the dependency chain described above.
- Without L27: 524 tokens; removes `(int x, int y)[] input =` from the dependency chain described above.
- Without L28: 538 tokens; removes `{` from the dependency chain described above.
- Without L29: 443 tokens; removes `(3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6), (-6, -2), (2, -2),` from the dependency chain described above.
- Without L30: 504 tokens; removes `(7, -1), (-3, 4), (2, 8), (-6, 3),` from the dependency chain described above.
- Without L31: 537 tokens; removes `};` from the dependency chain described above.
- Without L32: 502 tokens; removes `var points = input.OrderBy(p => p.x).ThenBy(p => p.y).ToList();` from the dependency chain described above.
- Without L33: 528 tokens; removes `var lower = Chain(points);` from the dependency chain described above.
- Without L34: 519 tokens; removes `var upper = Chain(points.AsEnumerable().Reverse());` from the dependency chain described above.
- Without L35: 525 tokens; removes `lower.RemoveAt(lower.Count - 1);` from the dependency chain described above.
- Without L36: 525 tokens; removes `upper.RemoveAt(upper.Count - 1);` from the dependency chain described above.
- Without L37: 531 tokens; removes `lower.AddRange(upper);` from the dependency chain described above.
