# Task B selection — 92_bst_traversal / Lua

## Common answer requirements

Trace the deletion of 27 after deletion of 6, show successor selection and reconnection, and connect the resulting tree to preorder and height.

## Source evidence

The insertion data and placement rules establish the tree. After removing 6, the successor of 27 is 31, reached as the leftmost node below its right child 39. Copy 31 into the deleted key position and splice 31’s right child 34 back as the left child of 39. The local subtree is rooted at 31 with children 13 and 39. The post-deletion preorder visits 31, 13, 39, 34, 45 in that subtree, and the resulting tree has height four nodes.

## Minimization

Selected complete lines of `main.lua`: L1, L2, L3, L4, L5, L6, L7, L8, L9, L11, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L30, L31, L32, L33, L35, L37, L39, L40, L41, L42, L44, L45, L60, L61, L62, L63, L64, L65. The selected construction, search, successor splice and traversal calls support the trace. Deleting the specified keys never searches an absent subtree, so a separate missing-key return is unnecessary here. The recursive insertion, preorder and height base cases still support their required facts. Output-only joining does not affect traversal.

The selected excerpt measures **627 tokens** with `metric/tokenizer.py`.
