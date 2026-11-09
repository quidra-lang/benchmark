# Task B: 43_run_length_encoding / J

The second input is twelve W, then B, then twelve W, then BBB. Maximal-run encoding produces `12W1B12W3B`. Decoding scans each complete decimal count, so 12 is one count rather than separate 1 and 2; repetition reconstructs `WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The full line is `WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The named decoded value is obtained from encoded, not from copying the original.

The user-defined encoder closes a run only when its symbol changes or input ends; decoder advances across all digit characters before repeating the following symbol.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L30,L31,L32,L33,L34,L35,L36.

- L1: `encode =: 3 : 0`
- L2: `result =. ''`
- L3: `i =. 0`
- L4: `while. i<#y do.`
- L5: `end =. i+1`
- L6: `while. end<#y do.`
- L7: `if. (end{y)~:i{y do. break. end.`
- L8: `end =. >:end`
- L9: `end.`
- L10: `result =. result,(":end-i),i{y`
- L11: `i =. end`
- L12: `end.`
- L13: `result`
- L14: `)`
- L15: `decode =: 3 : 0`
- L16: `result =. ''`
- L17: `i =. 0`
- L18: `while. i<#y do.`
- L19: `count =. 0`
- L20: `while. (i{y)e.'0123456789' do.`
- L21: `count =. (10*count)+'0123456789'i.i{y`
- L22: `i =. >:i`
- L23: `end.`
- L24: `result =. result,count$i{y`
- L25: `i =. >:i`
- L26: `end.`
- L27: `result`
- L28: `)`
- L30: `values =. 'AAABBBCCCD';'WWWWWWWWWWWWBWWWWWWWWWWWWBBB';'ALGORITHM';'MISSISSIPPI';'XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ'`
- L31: `for_box. values do.`
- L32: `value =. >box`
- L33: `encoded =. encode value`
- L34: `decoded =. decode encoded`
- L35: `smoutput value,' -> ',encoded,' -> ',decoded`
- L36: `end.`

Minimization: The encoder and decoder bodies, this input binding and their call/output chain are needed. Other sample literals are omitted when independent complete lines permit it. The selected complete original lines, in source order, cost 343 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 353, and the complete source costs 360. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
