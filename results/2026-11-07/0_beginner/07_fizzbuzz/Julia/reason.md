# Task B: 07_fizzbuzz / Julia

The fallback reference is the current loop integer, not a literal result string. At input 1 it resolves to the loop binding whose current value is 1; the numeric fallback therefore writes 1. The quoted Fizz/Buzz text belongs to other branches and does not define or shadow that integer name.

for n binds n; println(n) resolves to this loop binding.

Evidence is from `main.jl`, L1,L9.

- L1: `for n = 1:30`
- L9: `println(n)`

Minimization: Only the binding site and the numeric fallback expression are necessary for this name-resolution question. Divisibility decisions and literal-result branches are unrelated to where this reference resolves. The selected complete original lines, in source order, cost 18 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 89, and the complete source costs 94. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
