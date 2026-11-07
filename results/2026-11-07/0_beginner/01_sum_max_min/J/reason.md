# Task B: 01_sum_max_min / J

The collection contains 5 twice. The reduction consumes both positions independently, so the accumulator includes +5 twice; duplicate values do not collapse. Its implicit traversal ends at the collection length of ten and advances once per element, without an extra element.

In J the positions are 3 and 6, using zero-based indices. +/ reduces the whole numeric vector, so its library traversal replaces an explicit indexed loop.

Evidence is from `main.ijs`, L5,L6.

- L5: `values =: 17 _8 42 5 _23 36 5 0 _11 29`
- L6: `total =: +/values`

Minimization: The literal establishes both occurrence positions and the ten-element bound; the total-producing reduction establishes traversal and accumulation. Max/min calculations and output labels add no evidence about processing either 5. The selected complete original lines, in source order, cost 41 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 41, and the complete source costs 110. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
