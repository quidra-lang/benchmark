# Task B: 10_fibonacci / R

The sequence starts with F(1)=F(2)=1. Appending the sum of the two preceding values gives F(3)=2; the count bound stops after exactly 30 terms. The named total is the sum of that finished sequence, 2178308, available alongside the sequence for output. All these values are exact integers at this scale; mathematical integrality alone is not a universal static type guarantee.

The literals create ordinary numeric doubles, not a statically declared integer vector. Additions and sum remain exact because these integers are far below the exact-double integer limit.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L7.

- L1: `terms <- c(1, 1)`
- L2: `while (length(terms) < 30) {`
- L3: `n <- length(terms)`
- L4: `terms <- c(terms, terms[n - 1] + terms[n])`
- L5: `}`
- L7: `total <- sum(terms)`

Minimization: Initialization, bounded next-term construction and total production are sufficient. Printing is omitted because the question stops at values made available for output; no list of all thirty terms is required. The selected complete original lines, in source order, cost 76 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 107, and the complete source costs 126. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
