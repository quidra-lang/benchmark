# Task B: 79_n_queens / Julia

Reverse the per-row candidate column traversal while retaining the same empty board state, column/diagonal rejection and full recursion/restoration. Descending traversal makes the first size-eight solution `[7,3,0,2,5,1,6,4]` in zero-based columns, the horizontal reflection of the ascending first solution. Retain its independent first-solution snapshot before later branches overwrite working positions, then render rows at those columns. Exhaustive counts remain N=4:2,5:10,6:4,7:40,8:92: candidate order changes discovery order, not which placements are examined.

Reverse 0:n-1 in solve. The shared positions vector is written per depth, but only earlier rows are read for rejection and append!(first_solution,columns) copies the scalar positions into independent storage.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28,L29,L30,L31,L32,L33,L34,L35,L36.

- L1: `function solve_queens(n)`
- L2: `columns = fill(-1, n)`
- L3: `first_solution = Int[]`
- L4: `solutions = 0`
- L5: `function place(row)`
- L6: `if row == n`
- L7: `solutions += 1`
- L8: `isempty(first_solution) && append!(first_solution, columns)`
- L9: `return`
- L10: `end`
- L11: `for column = 0:(n-1)`
- L12: `if all(`
- L13: `previous ->`
- L14: `columns[previous+1] != column &&`
- L15: `abs(columns[previous+1]-column) != row-previous,`
- L16: `0:(row-1),`
- L17: `)`
- L18: `columns[row+1] = column`
- L19: `place(row+1)`
- L20: `end`
- L21: `end`
- L22: `end`
- L23: `place(0)`
- L24: `return solutions, first_solution`
- L25: `end`
- L28: `first_eight = Int[]`
- L29: `for n = 4:8`
- L30: `solutions, first_solution = solve_queens(n)`
- L31: `println("N=", n, ": ", solutions, " solutions")`
- L32: `n == 8 && (first_eight = first_solution)`
- L33: `end`
- L34: `for column in first_eight`
- L35: `println(repeat(".", column), "Q", repeat(".", 7-column))`
- L36: `end`

Minimization: The recursive enumerator, candidate validity, working-state restoration/overwrite, first snapshot, requested sizes and board rendering are needed for this complete ordering change. No unrelated source is selected. The selected complete original lines, in source order, cost 386 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 392, and the complete source costs 398. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
