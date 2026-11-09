# Task B: 92_bst_traversal / R

The inorder item must be a captured scalar key, not a live node reference whose key may later change during deletion. Current traversal already accumulates/returns key values independently, so no deeper tree copy is needed. Retain the original inorder result before deletion, then print that saved value sequence afterward instead of rerunning traversal on the changed tree.

c(inorder(node$left),node$value,inorder(node$right)) produces an ordinary numeric value vector; R value semantics keep that result independent of later node environment mutation.

Evidence is from `main.R`, L41.

- L41: `inorder = c(left, node$value, right),`

Minimization: The item expression and its value/result context suffice. Node-deletion implementation and copying the entire tree are outside the requested item-capture analysis. The selected complete original lines, in source order, cost 19 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 19, and the complete source costs 1012. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
