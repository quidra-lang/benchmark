# Task B selection: 86_convex_hull / Go

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.go`. Selected original locations: L8,L9,L10,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35.

- L8: `func cross(o, a, b [2]int) int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `	return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `	points := [][2]int{{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `		{-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `	sort.Slice(points, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `		if points[i][0] != points[j][0] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `			return points[i][0] < points[j][0]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `		return points[i][1] < points[j][1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `	lower, upper := [][2]int{}, [][2]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `	for _, p := range points {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `		for len(lower) >= 2 && cross(lower[len(lower)-2], lower[len(lower)-1], p) <= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `			lower = lower[:len(lower)-1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `		lower = append(lower, p)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `	for i := len(points) - 1; i >= 0; i-- {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `		p := points[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `		for len(upper) >= 2 && cross(upper[len(upper)-2], upper[len(upper)-1], p) <= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `			upper = upper[:len(upper)-1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `		upper = append(upper, p)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `	hull := append(lower[:len(lower)-1], upper[:len(upper)-1]...)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **603 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 579 tokens. The contiguous original span L8–L35 costs 612 tokens; the complete original source costs 794 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 581 tokens; removes `func cross(o, a, b [2]int) int {` from the dependency chain described above.
- Without L9: 550 tokens; removes `return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])` from the dependency chain described above.
- Without L10: 601 tokens; removes `}` from the dependency chain described above.
- Without L13: 515 tokens; removes `points := [][2]int{{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},` from the dependency chain described above.
- Without L14: 547 tokens; removes `{-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}}` from the dependency chain described above.
- Without L15: 581 tokens; removes `sort.Slice(points, func(i, j int) bool {` from the dependency chain described above.
- Without L16: 579 tokens; removes `if points[i][0] != points[j][0] {` from the dependency chain described above.
- Without L17: 580 tokens; removes `return points[i][0] < points[j][0]` from the dependency chain described above.
- Without L18: 599 tokens; removes `}` from the dependency chain described above.
- Without L19: 581 tokens; removes `return points[i][1] < points[j][1]` from the dependency chain described above.
- Without L20: 599 tokens; removes `})` from the dependency chain described above.
- Without L21: 578 tokens; removes `lower, upper := [][2]int{}, [][2]int{}` from the dependency chain described above.
- Without L22: 587 tokens; removes `for _, p := range points {` from the dependency chain described above.
- Without L23: 555 tokens; removes `for len(lower) >= 2 && cross(lower[len(lower)-2], lower[len(lower)-1], p) <= 0 {` from the dependency chain described above.
- Without L24: 586 tokens; removes `lower = lower[:len(lower)-1]` from the dependency chain described above.
- Without L25: 599 tokens; removes `}` from the dependency chain described above.
- Without L26: 589 tokens; removes `lower = append(lower, p)` from the dependency chain described above.
- Without L27: 600 tokens; removes `}` from the dependency chain described above.
- Without L28: 574 tokens; removes `for i := len(points) - 1; i >= 0; i-- {` from the dependency chain described above.
- Without L29: 592 tokens; removes `p := points[i]` from the dependency chain described above.
- Without L30: 555 tokens; removes `for len(upper) >= 2 && cross(upper[len(upper)-2], upper[len(upper)-1], p) <= 0 {` from the dependency chain described above.
- Without L31: 586 tokens; removes `upper = upper[:len(upper)-1]` from the dependency chain described above.
- Without L32: 599 tokens; removes `}` from the dependency chain described above.
- Without L33: 589 tokens; removes `upper = append(upper, p)` from the dependency chain described above.
- Without L34: 600 tokens; removes `}` from the dependency chain described above.
- Without L35: 573 tokens; removes `hull := append(lower[:len(lower)-1], upper[:len(upper)-1]...)` from the dependency chain described above.
