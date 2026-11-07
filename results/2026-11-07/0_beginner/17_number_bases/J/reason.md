# Task B: 17_number_bases / J

For 43981 the hexadecimal digits are ABCD, so the affected field becomes `hex=abcd`. Change only the hexadecimal digit alphabet or case-selecting conversion stage feeding the existing common output. Keep decimal, binary and octal unchanged; retain the existing zero representation `0`, omit any prefix, and add no leading zeros.

The base helper indexes its alphabet after #. inverse digit extraction, with a dedicated zero path. Lowercase A-F only in that alphabet (or only in the hexadecimal result) while leaving 0-9 and other bases intact.

Evidence is from `main.ijs`, L1,L2,L3,L4,L7,L8.

- L1: `base =: 4 : 0`
- L2: `if. y=0 do. '0' return. end.`
- L3: `digits =. (x&#.^:_1) y`
- L4: `digits { '0123456789ABCDEF'`
- L7: `for_n. 0 10 255 1000 43981 65535 do.`
- L8: `smoutput (":n), ': bin=', (2 base n), ' oct=', (8 base n), ' hex=', 16 base n`

Minimization: The hexadecimal-producing operation and its output consumer are necessary. J also needs the custom digit alphabet and zero branch; standard-library base formatting in Julia/R supplies those contracts without extra source. The selected complete original lines, in source order, cost 153 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 165, and the complete source costs 175. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
