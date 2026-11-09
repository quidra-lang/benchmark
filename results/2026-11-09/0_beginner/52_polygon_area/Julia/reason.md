# Task B: 52_polygon_area / Julia

For an empty vertex sequence the edge loop has zero iterations. Therefore neither the first vertex access nor the last-to-first/wrap access inside its body is evaluated; there is no prior first-vertex read and no explicit rejection. The initialized twice-area/cross-sum 0 and perimeter 0.0 reach formatting, giving polygon 1 area=0.0 and perimeter=0.000. These are default results, not a validation error.

eachindex(vertices) is empty, so mod1(i+1,length(vertices)) never runs with zero length; defaults flow to @printf.

Evidence is from `main.jl`, L9,L10,L11,L12,L13,L17,L18,L19,L20,L21,L22,L23.

- L9: `for (number, vertices) in enumerate(polygons)`
- L10: `twice_area, perimeter = 0, 0.0`
- L11: `for i in eachindex(vertices)`
- L12: `x, y = vertices[i]`
- L13: `next_x, next_y = vertices[mod1(i+1, length(vertices))]`
- L17: `end`
- L18: `@printf(`
- L19: `"polygon %d: area=%.1f perimeter=%.3f\n",`
- L20: `number,`
- L21: `abs(twice_area)/2,`
- L22: `perimeter`
- L23: `)`

Minimization: Initialization, loop entry, the endpoint accesses and loop exit/output are enough to determine empty behavior. Edge arithmetic inside the skipped body and actual nonempty polygon literals are unnecessary. The selected complete original lines, in source order, cost 156 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 221, and the complete source costs 390. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
