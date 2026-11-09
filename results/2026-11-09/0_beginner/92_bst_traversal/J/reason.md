# Task B: 92_bst_traversal / J

The inorder item must be a captured scalar key, not a live node reference whose key may later change during deletion. Current traversal already accumulates/returns key values independently, so no deeper tree copy is needed. Retain the original inorder result before deletion, then print that saved value sequence afterward instead of rerunning traversal on the changed tree.

The result vector appends node{keys, a numeric scalar value, and returns that vector; it does not append a node identifier to be dereferenced later.

Evidence is from `main.ijs`, L4,L7,L10.

- L4: `result =. i.0`
- L7: `if. mode=0 do. result =. result,node{keys end.`
- L10: `result`

Minimization: The item expression and its value/result context suffice. Node-deletion implementation and copying the entire tree are outside the requested item-capture analysis. The selected complete original lines, in source order, cost 32 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 108, and the complete source costs 904. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
