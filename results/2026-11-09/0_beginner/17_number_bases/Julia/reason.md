# Task B: 17_number_bases / Julia

For 43981 the hexadecimal digits are ABCD, so the affected field becomes `hex=abcd`. Change only the hexadecimal digit alphabet or case-selecting conversion stage feeding the existing common output. Keep decimal, binary and octal unchanged; retain the existing zero representation `0`, omit any prefix, and add no leading zeros.

Change uppercase(string(n;base=16)) to a lowercase hexadecimal result; the same named hexadecimal operand then reaches println.

Evidence is from `main.jl`, L2,L3.

- L2: `hex = uppercase(string(n; base = 16))`
- L3: `println("$n: bin=$(string(n; base = 2)) oct=$(string(n; base = 8)) hex=$hex")`

Minimization: The hexadecimal-producing operation and its output consumer are necessary. J also needs the custom digit alphabet and zero branch; standard-library base formatting in Julia/R supplies those contracts without extra source. The selected complete original lines, in source order, cost 70 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 70, and the complete source costs 111. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
