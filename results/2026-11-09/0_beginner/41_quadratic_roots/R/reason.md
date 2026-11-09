# Task B: 41_quadratic_roots / R

For a=-2,b=5,c=4 the discriminant b²-4ac is 57. sqrt(57) is real; the denominator 2a is -4, so the unformatted candidates are approximately -0.6374586 and 3.1374586. The source retains their fractional parts and orders the larger as x1 before display. Integer-valued input/discriminant does not mean the root divisions may truncate.

The coefficient literals explicitly use R integers; the discriminant remains integer here, while sqrt and / are real operations. max/min order the candidates before sprintf.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L8,L9,L10,L11.

- L1: `coefficients <- list(c(1L, -3L, -10L), c(-2L, 5L, 4L), c(3L, 1L, -2L), c(4L, -12L, 9L), c(1L, 2L, 5L), c(-2L, 3L, -4L))`
- L2: `for (coefficient in coefficients) {`
- L3: `a <- coefficient[1]`
- L4: `b <- coefficient[2]`
- L5: `c_value <- coefficient[3]`
- L6: `discriminant <- b * b - 4L * a * c_value`
- L8: `if (discriminant > 0) {`
- L9: `first <- (-b + sqrt(discriminant)) / (2 * a)`
- L10: `second <- (-b - sqrt(discriminant)) / (2 * a)`
- L11: `cat(sprintf("x1 = %.4f, x2 = %.4f\n", max(first, second), min(first, second)))`

Minimization: The coefficient binding, discriminant, positive-discriminant branch, root arithmetic and ordering are needed. Other solution cases and unrelated input tuples need no trace, except when on the same literal line. The selected complete original lines, in source order, cost 288 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 318, and the complete source costs 470. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
