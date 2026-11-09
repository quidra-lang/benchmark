# Task B: 10_fibonacci / Julia

The sequence starts with F(1)=F(2)=1. Appending the sum of the two preceding values gives F(3)=2; the count bound stops after exactly 30 terms. The named total is the sum of that finished sequence, 2178308, available alongside the sequence for output. All these values are exact integers at this scale; mathematical integrality alone is not a universal static type guarantee.

The literal [1,1] creates an Int vector, push! preserves that element type, and sum returns an Int here. The while length<30 guard bounds appends.

Evidence is from `main.jl`, L2,L3,L4,L5,L7.

- L2: `terms = [1, 1]`
- L3: `while length(terms) < 30`
- L4: `push!(terms, terms[end-1] + terms[end])`
- L5: `end`
- L7: `total = sum(terms)`

Minimization: Initialization, bounded next-term construction and total production are sufficient. Printing is omitted because the question stops at values made available for output; no list of all thirty terms is required. The selected complete original lines, in source order, cost 61 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 75, and the complete source costs 99. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
