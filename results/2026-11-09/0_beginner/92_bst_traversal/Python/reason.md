# Task B selection: 92_bst_traversal / Python

## Answer requirements

Suppose the original inorder result must be retained across deletion of 27 and printed later. Locate the expression that emits or records each inorder item, and explain where and how to capture its key value for later output rather than retaining a live node reference whose key can be replaced. If values are already retained independently, explain why no capture change is needed. Focus on that item expression; do not copy the whole tree.

## Answer and source evidence

Python inorder already returns a newly constructed list of integer node.key values; retaining that list retains immutable key values even when deletion later rebinds a node key. It does not retain live Node objects. Quidra traverse returns int[] values passed by value to show, so retain that result before deletion instead of immediately discarding it after output. No node/deep-tree copy is needed; the item value is already captured independently. The selected item/traversal/typed renderer establishes the required value boundary.



Selected `main.py` lines: 40, 41. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
