# Task B: 29_matrix_multiply / J

C at row 1, column 2 combines A row [3,-2,5,1] with B column [4,2,-1,7]: products 12,-4,-5,7 sum to 10. Row-major rendering places this value in the second field of the first printed row. The zero at A row 2, column 3 takes ordinary dense matrix-product semantics; there is no source-level conditional that skips a zero multiplicand. A library may choose its own internal implementation, which this source does not expose.

The product uses +/ . * (multiply paired elements then sum), and its formatted matrix is emitted in row order. No zero test surrounds that product.

Evidence is from `main.ijs`, L1,L2,L3,L4.

- L1: `a =: 3 4$3 _2 5 1 _4 7 0 6 2 9 _8 _3`
- L2: `b =: 4 2$1 4 _5 2 6 _1 0 7`
- L3: `product =: a +/ . * b`
- L4: `smoutput '5.0' 8!:2 product`

Minimization: Both operand literals, the matrix product and row rendering establish the requested four pairs, reduction and field position. No helper source is needed for standard dense-multiplication semantics. The selected complete original lines, in source order, cost 91 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 91, and the complete source costs 91. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
