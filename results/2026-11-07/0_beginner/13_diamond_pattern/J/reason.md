# Task B: 13_diamond_pattern / J

The row size grows 1,2,3,4,5 and then shrinks 4,3,2,1; the second range omits 5 so the widest row is not repeated. Prefix each emitted row with `row k: ` while counting emissions from 1. The first shrinking row has size 4 but ordinal 6. Keep the existing size-based leading spaces and star count after that prefix.

The existing row binder already ranges from 1 through 9. Its separate derived i=min(row,10-row) is the size, so use row as k and preserve i for shape.

Evidence is from `main.ijs`, L2,L3,L4,L5.

- L2: `n =. 5`
- L3: `for_row. >:i.<:2*n do.`
- L4: `i =. row <. (2*n)-row`
- L5: `smoutput ((n-i)$' '), ((2*i)-1)$'*'`

Minimization: The size parameter, expansion/contraction traversal and shape output define the complete routine. Nothing outside this loop contributes to the row ordinal or shape. The selected complete original lines, in source order, cost 69 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 69, and the complete source costs 89. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
