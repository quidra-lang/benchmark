# Task B: 17_number_bases / R

For 43981 the hexadecimal digits are ABCD, so the affected field becomes `hex=abcd`. Change only the hexadecimal digit alphabet or case-selecting conversion stage feeding the existing common output. Keep decimal, binary and octal unchanged; retain the existing zero representation `0`, omit any prefix, and add no leading zeros.

The common sprintf line uses %X for hexadecimal; %x supplies lowercase while retaining the other conversion specifiers and width rules.

Evidence is from `main.R`, L4.

- L4: `cat(sprintf("%d: bin=%s oct=%o hex=%X\n", n, binary, as.integer(n), as.integer(n)))`

Minimization: The hexadecimal-producing operation and its output consumer are necessary. J also needs the custom digit alphabet and zero branch; standard-library base formatting in Julia/R supplies those contracts without extra source. The selected complete original lines, in source order, cost 51 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 51, and the complete source costs 155. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
