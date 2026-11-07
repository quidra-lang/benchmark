# Task B: 09_reverse_words / J

The first reversal acts on the character sequence: the final word line becomes enil and its preceding space moves after those reversed letters. The second first splits on spaces, reverses the sequence of whole word tokens, and joins them with single spaces. Its first token is therefore line, with the four letters still in their original order.

|. sentence reverses characters; the cut operation creates boxed whole words before |. reverses their order, and join inserts single spaces.

Evidence is from `main.ijs`, L1,L2,L3.

- L1: `sentence =: 'every program starts with a single line'`
- L2: `smoutput |. sentence`
- L3: `smoutput }. ; (<' ') ,&.> |. ;: sentence`

Minimization: The shared input and the two neighboring reverse/rejoin operations establish the unit of reversal. No per-character trace or unrelated input is needed. The selected complete original lines, in source order, cost 49 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 49, and the complete source costs 49. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
