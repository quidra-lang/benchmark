# Task B: 32_tower_of_hanoi / J

For (4,A,C,B), first solve (3,A,B,C), emit the move of disk 4 from A to C, then solve (3,B,C,A). At disk count zero the base case returns zero and emits no move. The returned count is left count +1+ right count =15. Peg letters are role arguments, not shared mutable peg storage; rebinding a callee role does not change the caller bindings.

The J verb unpacks the count/labels and recurses on boxed value arguments. The top-level call is included where separately written.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9.

- L1: `hanoi =: 3 : 0`
- L2: `'n source target auxiliary' =. y`
- L3: `if. n=0 do. 0 return. end.`
- L4: `first =. hanoi (n-1);source;auxiliary;target`
- L5: `smoutput 'move disk ', (":n), ' from ',source,' to ',target`
- L6: `last =. hanoi (n-1);auxiliary;target;source`
- L7: `first+1+last`
- L8: `)`
- L9: `moves =: hanoi 4;'A';'C';'B'`

Minimization: The recursive routine, base case, move output and top-level role assignment are needed. Unrelated summary formatting is omitted where it is a separate statement. The selected complete original lines, in source order, cost 141 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 141, and the complete source costs 156. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
