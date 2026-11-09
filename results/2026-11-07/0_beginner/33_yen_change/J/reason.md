# Task B: 33_yen_change / J

For original 506, the 500-yen iteration obtains quotient 1 and remainder 6, emits the 500×1 item and adds one to the piece total. At 100 yen the quotient is zero and remainder stays 6; the positive-count guard suppresses that item and adds nothing. The changing remainder is a different binding from the retained original amount used in the line label.

remaining is updated with denomination|remaining while n keeps 506; result begins from n, and the nonzero conditional appends only actual pieces.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10.

- L2: `for_amount. 3780 15420 99999 506 48263 do.`
- L3: `remaining =. amount`
- L4: `pieces =. 0`
- L5: `result =. (":amount),' yen:'`
- L6: `for_face. 10000 5000 1000 500 100 50 10 5 1 do.`
- L7: `count =. <.remaining%face`
- L8: `remaining =. face|remaining`
- L9: `pieces =. pieces+count`
- L10: `if. count>0 do. result =. result,' ',(":face),'x',":count end.`

Minimization: The input/original label, remainder initialization, denomination order, quotient/remainder update and nonzero branch are needed. Later denomination cases need no separate enumeration. The selected complete original lines, in source order, cost 175 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 175, and the complete source costs 220. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
