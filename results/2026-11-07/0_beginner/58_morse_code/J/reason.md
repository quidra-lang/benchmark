# Task B: 58_morse_code / J

The decoder should take Morse text as its message input, split words on the existing slash delimiter, split each word into complete space-delimited letter-code tokens, perform exact reverse lookup, then join decoded letters without separators and decoded words with one space. Thus `.` maps independently to E and `.-` to A; no prefix match or original-letter fallback is appropriate. The existing stages already meet these matching/joining requirements; only expose their encoded-input boundary as needed.

codes i.token compares whole boxed code strings for exact equality, not prefixes. The custom split/join helpers establish the word and letter boundaries.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L14,L15,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L34.

- L1: `split =: 4 : 0`
- L2: `result =. 0$<''`
- L3: `start =. 0`
- L4: `for_position. I.x E.y do.`
- L5: `result =. result,< (position-start){.start}.y`
- L6: `start =. position+#x`
- L7: `end.`
- L8: `result,<start}.y`
- L9: `)`
- L10: `join =: 4 : 0`
- L11: `(#x) }. ; (<x) ,&.> y`
- L12: `)`
- L14: `alphabet =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'`
- L15: `codes =. ' ' split '.- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.'`
- L23: `decodedwords =. 0$<''`
- L24: `for_box. ' / ' split encoded do.`
- L25: `tokens =. ' ' split >box`
- L26: `word =. ''`
- L27: `for_token. tokens do.`
- L28: `index =. codes i.token`
- L29: `word =. word,index{alphabet`
- L30: `end.`
- L31: `decodedwords =. decodedwords,<word`
- L32: `end.`
- L34: `smoutput ' ' join decodedwords`

Minimization: The code/letter association and complete decode path establish exact-token semantics and word restoration. Encoding from original message letters is intentionally omitted because it cannot justify an input-only decoder. The selected complete original lines, in source order, cost 359 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 475, and the complete source costs 482. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
