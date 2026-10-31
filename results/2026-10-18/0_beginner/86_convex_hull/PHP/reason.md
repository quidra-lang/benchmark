# Task B selection: 86_convex_hull / PHP

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32.

- L3: `function crossProduct(array $o, array $a, array $b): int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `    return ($a[0] - $o[0]) * ($b[1] - $o[1]) - ($a[1] - $o[1]) * ($b[0] - $o[0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `function chain(array $points): array` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    $result = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    foreach ($points as $point) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        while (` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            count($result) >= 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `            && crossProduct($result[count($result) - 2], $result[count($result) - 1], $point) <= 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        ) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            array_pop($result);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `        $result[] = $point;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `    return $result;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `$points = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    [3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1], [5, 6], [-6, -2], [2, -2],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    [7, -1], [-3, 4], [2, 8], [-6, 3],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `usort($points, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `$lower = chain($points);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `$upper = chain(array_reverse($points));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `array_pop($lower);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `array_pop($upper);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `$hull = array_merge($lower, $upper);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **516 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 498 tokens. The contiguous original span L3–L32 costs 518 tokens; the complete original source costs 696 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 490 tokens; removes `function crossProduct(array $o, array $a, array $b): int` from the dependency chain described above.
- Without L4: 514 tokens; removes `{` from the dependency chain described above.
- Without L5: 442 tokens; removes `return ($a[0] - $o[0]) * ($b[1] - $o[1]) - ($a[1] - $o[1]) * ($b[0] - $o[0]);` from the dependency chain described above.
- Without L6: 514 tokens; removes `}` from the dependency chain described above.
- Without L8: 503 tokens; removes `function chain(array $points): array` from the dependency chain described above.
- Without L9: 514 tokens; removes `{` from the dependency chain described above.
- Without L10: 507 tokens; removes `$result = [];` from the dependency chain described above.
- Without L11: 501 tokens; removes `foreach ($points as $point) {` from the dependency chain described above.
- Without L12: 510 tokens; removes `while (` from the dependency chain described above.
- Without L13: 503 tokens; removes `count($result) >= 2` from the dependency chain described above.
- Without L14: 470 tokens; removes `&& crossProduct($result[count($result) - 2], $result[count($result) - 1], $point) <= 0` from the dependency chain described above.
- Without L15: 510 tokens; removes `) {` from the dependency chain described above.
- Without L16: 504 tokens; removes `array_pop($result);` from the dependency chain described above.
- Without L17: 512 tokens; removes `}` from the dependency chain described above.
- Without L18: 504 tokens; removes `$result[] = $point;` from the dependency chain described above.
- Without L19: 513 tokens; removes `}` from the dependency chain described above.
- Without L20: 509 tokens; removes `return $result;` from the dependency chain described above.
- Without L21: 514 tokens; removes `}` from the dependency chain described above.
- Without L23: 509 tokens; removes `$points = [` from the dependency chain described above.
- Without L24: 419 tokens; removes `[3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1], [5, 6], [-6, -2], [2, -2],` from the dependency chain described above.
- Without L25: 480 tokens; removes `[7, -1], [-3, 4], [2, 8], [-6, 3],` from the dependency chain described above.
- Without L26: 513 tokens; removes `];` from the dependency chain described above.
- Without L27: 462 tokens; removes `usort($points, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));` from the dependency chain described above.
- Without L28: 504 tokens; removes `$lower = chain($points);` from the dependency chain described above.
- Without L29: 499 tokens; removes `$upper = chain(array_reverse($points));` from the dependency chain described above.
- Without L30: 507 tokens; removes `array_pop($lower);` from the dependency chain described above.
- Without L31: 507 tokens; removes `array_pop($upper);` from the dependency chain described above.
- Without L32: 498 tokens; removes `$hull = array_merge($lower, $upper);` from the dependency chain described above.
