# Task B: 41_quadratic_roots / Julia

For a=-2,b=5,c=4 the discriminant b²-4ac is 57. sqrt(57) is real; the denominator 2a is -4, so the unformatted candidates are approximately -0.6374586 and 3.1374586. The source retains their fractional parts and orders the larger as x1 before display. Integer-valued input/discriminant does not mean the root divisions may truncate.

Int coefficients give an Int discriminant; sqrt yields a floating result and / retains fractions. max/min order the candidates.

Evidence is from `main.jl`, L4,L5,L6,L8,L9,L10,L11.

- L4: `for (a, b, c) in`
- L5: `[(1, -3, -10), (-2, 5, 4), (3, 1, -2), (4, -12, 9), (1, 2, 5), (-2, 3, -4)]`
- L6: `discriminant = b*b - 4*a*c`
- L8: `if discriminant > 0`
- L9: `first = (-b + sqrt(Float64(discriminant))) / (2*a)`
- L10: `second = (-b - sqrt(Float64(discriminant))) / (2*a)`
- L11: `@printf("x1 = %.4f, x2 = %.4f\n", max(first, second), min(first, second))`

Minimization: The coefficient binding, discriminant, positive-discriminant branch, root arithmetic and ordering are needed. Other solution cases and unrelated input tuples need no trace, except when on the same literal line. The selected complete original lines, in source order, cost 227 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 254, and the complete source costs 409. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
