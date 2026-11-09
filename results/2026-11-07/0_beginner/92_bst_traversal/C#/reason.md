# Task B selection: 92_bst_traversal / C#

The inorder item is node.Key/key, appended to a List<int>/List<Integer>/MutableList<Int>, not the node itself. Primitive integer value/immutable boxing means later successor-key replacement cannot change an already retained item. No item-capture expression change is needed; retain the list beyond its current local scope to print it later.

The key type, traversal result type and inorder append are sufficient. Full deletion/tree/traversal algorithms are unnecessary to establish capture-by-value rather than live-node aliasing.

Selected complete source lines in `Program.cs`: 38, 43, 55. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
