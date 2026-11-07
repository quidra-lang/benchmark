# Task B: 53_closest_pair / Julia

Keep selection in squared-distance units and preserve strict nearest/farthest comparisons and ascending pair traversal, which retain the first lexicographic pair on a tie. At the two reporting sites remove the square root and render the retained minimum/maximum squared value as an integer instead of fixed four-decimal Euclidean distance. Pair identity and closest/farthest labels stay unchanged.

nearest/farthest store squared values and pair indices; replace sqrt(Float64(squared)) and %.4f at reporting with the squared integer and integer formatting.

Evidence is from `main.jl`, L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33.

- L16: `nearest, farthest = (0, 0, typemax(Int)), (0, 0, -1)`
- L17: `for i = 1:(length(points)-1)`
- L18: `for j = (i+1):length(points)`
- L19: `dx = points[i][1]-points[j][1]`
- L20: `dy = points[i][2]-points[j][2]`
- L21: `squared = dx*dx+dy*dy`
- L22: `if squared < nearest[3]`
- L23: `nearest = (i-1, j-1, squared)`
- L24: `end`
- L25: `if squared > farthest[3]`
- L26: `farthest = (i-1, j-1, squared)`
- L27: `end`
- L28: `end`
- L29: `end`
- L30: `for (label, pair) in [("closest", nearest), ("farthest", farthest)]`
- L31: `distance = sqrt(Float64(pair[3]))`
- L32: `@printf("%s: P%d P%d %.4f\n", label, pair[1], pair[2], distance)`
- L33: `end`

Minimization: Initialization/tie policy, squared selection and the two report expressions are necessary to show unit conversion is confined to output. Point coordinates are unnecessary because no specific pair result is requested. The selected complete original lines, in source order, cost 316 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 316, and the complete source costs 466. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
