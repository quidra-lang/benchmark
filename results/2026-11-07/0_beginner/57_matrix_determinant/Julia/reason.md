# Task B: 57_matrix_determinant / Julia

The one-entry base returns that entry. Each first-row column creates a minor by deleting the first row and that column, recursively evaluates it, multiplies by the corresponding first-row entry and adds/subtracts with alternating signs. For matrix 1 the first term is 2×det[[4,-2],[6,3]]=2×24=48. There is no division or pre-output rounding: all signed terms and the result remain exact integers for these inputs.

Julia uses one-based odd j for the positive sign; the Int matrix and integer multiplication/addition retain exact Int results within range.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L13,L14,L17.

- L1: `function laplace(matrix)`
- L2: `n = size(matrix, 1)`
- L3: `n == 1 && return matrix[1, 1]`
- L4: `total = 0`
- L5: `for j = 1:n`
- L6: `columns = [k for k = 1:n if k != j]`
- L7: `term = matrix[1, j] * laplace(matrix[2:end, columns])`
- L8: `total += isodd(j) ? term : -term`
- L9: `end`
- L10: `return total`
- L13: `matrices = [`
- L14: `[2 -3 1; 5 4 -2; -1 6 3],`
- L17: `]`

Minimization: The recursive routine and first-matrix literal are needed for the concrete first term. Other matrices can be omitted on separately written lines; the J literal necessarily shares its complete line with the other matrices. The selected complete original lines, in source order, cost 177 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 289, and the complete source costs 346. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
