# Task B: 15_gcd_lcm / J

The arguments become working values a=48 and b=180. Remainders are 48,36,12,0; each iteration replaces a with the former b and b with that remainder. When b reaches zero the loop stops and returns a=12. Zero is a valid working remainder and termination sentinel, whereas the final gcd is positive for these inputs; no positive-only working-value type or nonzero check is present.

The dyadic J verb takes x and y as its two arguments; b|a computes the Euclidean remainder, and the while guard tests b~:0.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9.

- L1: `gcd =: 4 : 0`
- L2: `a =. x`
- L3: `b =. y`
- L4: `while. b ~: 0 do.`
- L5: `remainder =. b|a`
- L6: `a =. b`
- L7: `b =. remainder`
- L8: `end.`
- L9: `a`

Minimization: The complete small gcd routine establishes argument binding, arithmetic, ordered state update and return. Call-site lcm calculations and formatting do not contribute to the requested gcd result. The selected complete original lines, in source order, cost 64 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 64, and the complete source costs 251. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
