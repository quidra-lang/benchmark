# Task B: 13_diamond_pattern / Julia

The row size grows 1,2,3,4,5 and then shrinks 4,3,2,1; the second range omits 5 so the widest row is not repeated. Prefix each emitted row with `row k: ` while counting emissions from 1. The first shrinking row has size 4 but ordinal 6. Keep the existing size-based leading spaces and star count after that prefix.

The concatenated ranges 1:n and (n-1):-1:1 supply sizes; enumerate them or increment an independent ordinal once per println, starting at 1.

Evidence is from `main.jl`, L1,L2,L3.

- L1: `n = 5`
- L2: `for i in vcat(1:n, (n-1):-1:1)`
- L3: `println(repeat(" ", n-i), repeat("*", 2*i-1))`

Minimization: The size parameter, expansion/contraction traversal and shape output define the complete routine. Nothing outside this loop contributes to the row ordinal or shape. The selected complete original lines, in source order, cost 62 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 62, and the complete source costs 64. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
