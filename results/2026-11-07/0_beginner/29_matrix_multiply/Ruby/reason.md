C(row 1,column 2) sums 3*4 + (-2)*2 + 5*(-1) + 1*7 = 10, and is emitted as the second width-five field of the first line. The zero in A(row 2,column 3) still follows the ordinary multiply/add path: no zero-test or conditional skip exists.

j enumerates output columns and k all four factors; products retains column order and the subsequent map/join prints that row. Integer multiplication evaluates both operands and does not short-circuit on zero.

Both operand matrices, all multiplication/addition loop operations and ordered row output are needed for the requested cell and absence of a zero skip. Other output scaffolding is excluded.
