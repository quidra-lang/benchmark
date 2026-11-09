# Task B: 85_text_justify / J

Splitting only on word-separating spaces retains punctuation: `names,` is one six-character token, including its comma. Greedy packing accepts a word only when letter lengths plus at least one space per existing gap fit width 30; otherwise it closes the current line and starts a fresh one. For a nonfinal multiword line, total spaces=30-sum(word lengths), gaps=word count-1, base=spaces quotient gaps, extra=spaces remainder gaps. Every gap receives base spaces and the leftmost extra gaps one more, giving exactly 30 characters. Vertical bars frame the completed text. Final/single-word lines instead join with ordinary single spaces and pad on the right to width 30.

The custom split produces whole boxed tokens. Packing tracks occupied length including minimal gaps; the fully justified branch inserts its gap spaces before each later word, using one-based gap test i<=extra.

Evidence is from `main.ijs`, L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42.

- L1: `split =: 4 : 0`
- L2: `<;._1 x,y`
- L3: `)`
- L6: `width =. 30`
- L7: `paragraph =. 'Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.'`
- L8: `words =. ' ' split paragraph`
- L9: `lines =. 0$<0$<''`
- L10: `current =. 0$<''`
- L11: `length =. 0`
- L12: `for_word. words do.`
- L13: `size =. #>word`
- L14: `candidate =. length+size+0<#current`
- L15: `if. candidate>width do.`
- L16: `lines =. lines,<current`
- L17: `current =. 0$<''`
- L18: `length =. 0`
- L19: `end.`
- L20: `length =. length+size+0<#current`
- L21: `current =. current,word`
- L22: `end.`
- L23: `if. #current do. lines =. lines,<current end.`
- L24: `for_index. i.#lines do.`
- L25: `line =. >index{lines`
- L26: `if. ((index+1)=#lines)+.1=#line do.`
- L27: `result =. }. ; (<' ') ,&.> line`
- L28: `result =. result,(width-#result)$' '`
- L29: `else.`
- L30: `letters =. +/#&>line`
- L31: `gaps =. <:#line`
- L32: `spaces =. width-letters`
- L33: `base =. <.spaces%gaps`
- L34: `extra =. gaps|spaces`
- L35: `result =. ''`
- L36: `for_i. i.#line do.`
- L37: `if. i>0 do. result =. result,(base+i<:extra)$' ' end.`
- L38: `result =. result,>i{line`
- L39: `end.`
- L40: `end.`
- L41: `smoutput '|',result,'|'`
- L42: `end.`

Minimization: Paragraph/token binding, greedy state transitions, final-line branch, quotient/remainder distribution and framing are necessary for this routine. No individual paragraph line needs a full formatting trace. The selected complete original lines, in source order, cost 559 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 570, and the complete source costs 577. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
