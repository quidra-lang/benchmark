# Task B: 50_roman_numerals / J

Encoding 1994 greedily appends M,CM,XC,IV as remaining becomes 994,94,4,0, producing MCMXCIV. The decoder receives that generated string. It maps symbols to 1000,100,1000,10,100,1,5 and subtracts a value only when followed by a greater one: 1000-100+1000-10+100-1+5=1994. Thus the numeric-to-Roman operation and Roman-to-numeric operation are separate stages joined by the encoded string.

The ordered value/symbol vectors contain subtractive pairs directly; the decoder builds singles from roman then uses its next-symbol comparison.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23.

- L2: `values =. 1000 900 500 400 100 90 50 40 10 9 5 4 1`
- L3: `symbols =. 'M';'CM';'D';'CD';'C';'XC';'L';'XL';'X';'IX';'V';'IV';'I'`
- L4: `for_number. 9 14 49 94 444 1994 2768 3999 do.`
- L5: `remaining =. number`
- L6: `roman =. ''`
- L7: `for_i. i.13 do.`
- L8: `while. remaining>:i{values do.`
- L9: `roman =. roman,>i{symbols`
- L10: `remaining =. remaining-i{values`
- L11: `end.`
- L12: `end.`
- L13: `decoded =. 0`
- L14: `singles =. ('IVXLCDM'i.roman){1 5 10 50 100 500 1000`
- L15: `for_i. i.#singles do.`
- L16: `current =. i{singles`
- L17: `next =. 0`
- L18: `if. (i+1)<#singles do. next =. (i+1){singles end.`
- L19: `if. current<next do. decoded =. decoded-current`
- L20: `else. decoded =. decoded+current`
- L21: `end.`
- L22: `end.`
- L23: `smoutput (":number),' -> ',roman,' -> ',":decoded`

Minimization: The conversion tables, complete encoder/decoder algorithms and the call boundary are needed to trace this subtractive case. Unrelated input literals/output labels are omitted where independent lines allow it. The selected complete original lines, in source order, cost 379 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 379, and the complete source costs 399. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
