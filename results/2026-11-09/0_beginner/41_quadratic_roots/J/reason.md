# Task B: 41_quadratic_roots / J

For a=-2,b=5,c=4 the discriminant b²-4ac is 57. sqrt(57) is real; the denominator 2a is -4, so the unformatted candidates are approximately -0.6374586 and 3.1374586. The source retains their fractional parts and orders the larger as x1 before display. Integer-valued input/discriminant does not mean the root divisions may truncate.

The denominator explicitly uses 2.0*a; sqrt and % yield real candidates, then max/min order them.

Evidence is from `main.ijs`, L6,L7,L8,L9,L13,L14,L15,L16,L17.

- L6: `for_row. 6 3$1 _3 _10 _2 5 4 3 1 _2 4 _12 9 1 2 5 _2 3 _4 do.`
- L7: `'a b c' =. row`
- L8: `d =. (b*b)-4*a*c`
- L9: `denominator =. 2.0*a`
- L13: `if. d>0 do.`
- L14: `root =. %:0.0+d`
- L15: `first =. ((-b)+root)%denominator`
- L16: `second =. ((-b)-root)%denominator`
- L17: `smoutput prefix,'x1 = ',(fixed first>.second),', x2 = ',fixed first<.second`

Minimization: The coefficient binding, discriminant, positive-discriminant branch, root arithmetic and ordering are needed. Other solution cases and unrelated input tuples need no trace, except when on the same literal line. The selected complete original lines, in source order, cost 190 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 232, and the complete source costs 411. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
