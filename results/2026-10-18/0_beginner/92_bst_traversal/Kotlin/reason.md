# Task B selection: 92_bst_traversal / Kotlin

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

End the named insertion/deletion/traversal helper before the following helper or top-level construction/output. These languages permit nested/local functions, so the explicit scope boundary establishes the selected caller/helper relationship rather than relying on indentation.

Source: `main.kt`. Selected original locations: L1,L3,L4,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L27,L28,L29,L31,L33,L35,L38,L39,L57,L58,L59,L60,L61,L62.

- L1: `class Node(var key: Int, var left: Node? = null, var right: Node? = null)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `fun insert(node: Node?, key: Int): Node {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    if (node == null) return Node(key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    if (key < node.key) node.left = insert(node.left, key) else node.right = insert(node.right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `fun delete(node: Node?, key: Int): Node? {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    if (node == null) return null` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    if (key < node.key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        node.left = delete(node.left, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    } else if (key > node.key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        node.right = delete(node.right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if (node.left == null) return node.right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        if (node.right == null) return node.left` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        var successor = node.right!!` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        while (successor.left != null) successor = successor.left!!` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        node.key = successor.key` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        node.right = delete(node.right, successor.key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `fun traverse(node: Node?, mode: Int, order: MutableList<Int>) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    if (node == null) return` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    if (mode == 1) order.add(node.key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    traverse(node.left, mode, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    traverse(node.right, mode, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `fun height(node: Node?): Int = if (node == null) 0 else 1 + maxOf(height(node.left), height(node.right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    var root: Node? = null` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    for (key in intArrayOf(50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34)) root = insert(root, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    root = delete(root, 6)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `    root = delete(root, 27)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    val after = mutableListOf<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    traverse(root, 1, after)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `    println("preorder after deletions: ${after.joinToString(" ")}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `    println("height after deletions: ${height(root)}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **698 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 694 tokens. The contiguous original span L1–L62 costs 1020 tokens; the complete original source costs 1022 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 660 tokens; removes `class Node(var key: Int, var left: Node? = null, var right: Node? = null)` from the dependency chain described above.
- Without L3: 676 tokens; removes `fun insert(node: Node?, key: Int): Node {` from the dependency chain described above.
- Without L4: 680 tokens; removes `if (node == null) return Node(key)` from the dependency chain described above.
- Without L5: 651 tokens; removes `if (key < node.key) node.left = insert(node.left, key) else node.right = insert(node.right, key)` from the dependency chain described above.
- Without L6: 693 tokens; removes `return node` from the dependency chain described above.
- Without L7: 696 tokens; removes `}` from the dependency chain described above.
- Without L9: 675 tokens; removes `fun delete(node: Node?, key: Int): Node? {` from the dependency chain described above.
- Without L10: 683 tokens; removes `if (node == null) return null` from the dependency chain described above.
- Without L11: 683 tokens; removes `if (key < node.key) {` from the dependency chain described above.
- Without L12: 680 tokens; removes `node.left = delete(node.left, key)` from the dependency chain described above.
- Without L13: 679 tokens; removes `} else if (key > node.key) {` from the dependency chain described above.
- Without L14: 680 tokens; removes `node.right = delete(node.right, key)` from the dependency chain described above.
- Without L15: 691 tokens; removes `} else {` from the dependency chain described above.
- Without L16: 678 tokens; removes `if (node.left == null) return node.right` from the dependency chain described above.
- Without L17: 678 tokens; removes `if (node.right == null) return node.left` from the dependency chain described above.
- Without L18: 685 tokens; removes `var successor = node.right!!` from the dependency chain described above.
- Without L19: 675 tokens; removes `while (successor.left != null) successor = successor.left!!` from the dependency chain described above.
- Without L20: 686 tokens; removes `node.key = successor.key` from the dependency chain described above.
- Without L21: 678 tokens; removes `node.right = delete(node.right, successor.key)` from the dependency chain described above.
- Without L22: 695 tokens; removes `}` from the dependency chain described above.
- Without L23: 693 tokens; removes `return node` from the dependency chain described above.
- Without L24: 696 tokens; removes `}` from the dependency chain described above.
- Without L26: 669 tokens; removes `fun traverse(node: Node?, mode: Int, order: MutableList<Int>) {` from the dependency chain described above.
- Without L27: 685 tokens; removes `if (node == null) return` from the dependency chain described above.
- Without L28: 678 tokens; removes `if (mode == 1) order.add(node.key)` from the dependency chain described above.
- Without L29: 684 tokens; removes `traverse(node.left, mode, order)` from the dependency chain described above.
- Without L31: 684 tokens; removes `traverse(node.right, mode, order)` from the dependency chain described above.
- Without L33: 696 tokens; removes `}` from the dependency chain described above.
- Without L35: 645 tokens; removes `fun height(node: Node?): Int = if (node == null) 0 else 1 + maxOf(height(node.left), height(node.right))` from the dependency chain described above.
- Without L38: 685 tokens; removes `var root: Node? = null` from the dependency chain described above.
- Without L39: 626 tokens; removes `for (key in intArrayOf(50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34)) root = insert(root, key)` from the dependency chain described above.
- Without L57: 685 tokens; removes `root = delete(root, 6)` from the dependency chain described above.
- Without L58: 684 tokens; removes `root = delete(root, 27)` from the dependency chain described above.
- Without L59: 682 tokens; removes `val after = mutableListOf<Int>()` from the dependency chain described above.
- Without L60: 686 tokens; removes `traverse(root, 1, after)` from the dependency chain described above.
- Without L61: 671 tokens; removes `println("preorder after deletions: ${after.joinToString(" ")}")` from the dependency chain described above.
- Without L62: 677 tokens; removes `println("height after deletions: ${height(root)}")` from the dependency chain described above.
