# Task B: 15_gcd_lcm / R

The arguments become working values a=48 and b=180. Remainders are 48,36,12,0; each iteration replaces a with the former b and b with that remainder. When b reaches zero the loop stops and returns a=12. Zero is a valid working remainder and termination sentinel, whereas the final gcd is positive for these inputs; no positive-only working-value type or nonzero check is present.

Ordinary numeric arguments and %% admit zero; the explicit temporary remainder preserves the old operands before a<-b and b<-remainder.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7.

- L1: `euclid <- function(a, b) {`
- L2: `while (b != 0) {`
- L3: `remainder <- a %% b`
- L4: `a <- b`
- L5: `b <- remainder`
- L6: `}`
- L7: `a`

Minimization: The complete small gcd routine establishes argument binding, arithmetic, ordered state update and return. Call-site lcm calculations and formatting do not contribute to the requested gcd result. The selected complete original lines, in source order, cost 58 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 58, and the complete source costs 255. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
