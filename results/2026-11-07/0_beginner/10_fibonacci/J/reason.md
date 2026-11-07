# Task B: 10_fibonacci / J

The sequence starts with F(1)=F(2)=1. Appending the sum of the two preceding values gives F(3)=2; the count bound stops after exactly 30 terms. The named total is the sum of that finished sequence, 2178308, available alongside the sequence for output. All these values are exact integers at this scale; mathematical integrality alone is not a universal static type guarantee.

J keeps integer arrays for these operations and this range. The two working terms are advanced after appending the previous term; +/ creates the total.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L12.

- L2: `a =. 1`
- L3: `b =. 1`
- L4: `terms =. i.0`
- L5: `for_n. i.30 do.`
- L6: `terms =. terms,a`
- L7: `next =. a+b`
- L8: `a =. b`
- L9: `b =. next`
- L10: `end.`
- L12: `total =. +/terms`

Minimization: Initialization, bounded next-term construction and total production are sufficient. Printing is omitted because the question stops at values made available for output; no list of all thirty terms is required. The selected complete original lines, in source order, cost 78 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 85, and the complete source costs 116. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
