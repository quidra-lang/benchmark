# Task B: 86_convex_hull / Julia

First sort coordinate pairs lexicographically, then traverse that sorted collection in reverse; the first two points are (8,4) and (7,-1). For each candidate, compare it with the last two chain points via the signed cross product. While chain length permits and cross<=0, remove the last chain point repeatedly, then append the current point. The reversal applies to coordinate-sorted order, not the original input order. Stop after the upper chain is built.

sort([...]) precedes chain(reverse(points)); pop! repeats on cross<=0 before push! appends each candidate.

Evidence is from `main.jl`, L3,L5,L6,L7,L8,L9,L10,L11,L12,L13,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L3: `cross_product(o, a, b) = (a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1])`
- L5: `function chain(points)`
- L6: `result = Tuple{Int,Int}[]`
- L7: `for point in points`
- L8: `while length(result) >= 2 && cross_product(result[end-1], result[end], point) <= 0`
- L9: `pop!(result)`
- L10: `end`
- L11: `push!(result, point)`
- L12: `end`
- L13: `return result`
- L17: `points = sort([`
- L18: `(3, 2),`
- L19: `(-6, 1),`
- L20: `(8, 4),`
- L21: `(0, 0),`
- L22: `(-3, 7),`
- L23: `(4, -3),`
- L24: `(1, -5),`
- L25: `(-2, 1),`
- L26: `(5, 6),`
- L27: `(-6, -2),`
- L28: `(2, -2),`
- L29: `(7, -1),`
- L30: `(-3, 4),`
- L31: `(2, 8),`
- L32: `(-6, 3),`
- L33: `])`
- L34: `lower, upper = chain(points), chain(reverse(points))`

Minimization: Cross product, full small chain helper, point data/sort and upper call are required to establish reverse order and repeated removal. Lower-chain concatenation, area and output are omitted. The selected complete original lines, in source order, cost 360 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 369, and the complete source costs 569. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
