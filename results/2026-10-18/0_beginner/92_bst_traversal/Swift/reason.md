# Task B selection: 92_bst_traversal / Swift

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

End the named insertion/deletion/traversal helper before the following helper or top-level construction/output. These languages permit nested/local functions, so the explicit scope boundary establishes the selected caller/helper relationship rather than relying on indentation.

Source: `main.swift`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L34,L35,L36,L37,L39,L41,L43,L44,L45,L46,L48,L49,L66,L67,L68,L69,L70,L71.

- L1: `class Node {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    var key: Int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    var left: Node?, right: Node?` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    init(_ key: Int) { self.key = key }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `func insert(_ node: Node?, _ key: Int) -> Node {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    guard let node else { return Node(key) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    if key < node.key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        node.left = insert(node.left, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        node.right = insert(node.right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `func delete(_ node: Node?, _ key: Int) -> Node? {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    guard let node else { return nil }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    if key < node.key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        node.left = delete(node.left, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    } else if key > node.key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        node.right = delete(node.right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        if node.left == nil { return node.right }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        if node.right == nil { return node.left }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        var successor = node.right!` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        while let left = successor.left { successor = left }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        node.key = successor.key` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        node.right = delete(node.right, successor.key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `func traverse(_ node: Node?, _ mode: Int, _ order: inout [Int]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    guard let node else { return }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    if mode == 1 { order.append(node.key) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    traverse(node.left, mode, &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    traverse(node.right, mode, &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `func height(_ node: Node?) -> Int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    guard let node else { return 0 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    return 1 + max(height(node.left), height(node.right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `var root: Node? = nil` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] { root = insert(root, key) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `root = delete(root, 6)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `root = delete(root, 27)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `var after = [Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `traverse(root, 1, &after)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `print("preorder after deletions: \(after.map(String.init).joined(separator: " "))")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `print("height after deletions: \(height(root))")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **761 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 757 tokens. The contiguous original span L1–L71 costs 1075 tokens; the complete original source costs 1075 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 755 tokens; removes `class Node {` from the dependency chain described above.
- Without L2: 753 tokens; removes `var key: Int` from the dependency chain described above.
- Without L3: 745 tokens; removes `var left: Node?, right: Node?` from the dependency chain described above.
- Without L4: 738 tokens; removes `init(_ key: Int) { self.key = key }` from the dependency chain described above.
- Without L5: 759 tokens; removes `}` from the dependency chain described above.
- Without L7: 734 tokens; removes `func insert(_ node: Node?, _ key: Int) -> Node {` from the dependency chain described above.
- Without L8: 741 tokens; removes `guard let node else { return Node(key) }` from the dependency chain described above.
- Without L9: 748 tokens; removes `if key < node.key {` from the dependency chain described above.
- Without L10: 743 tokens; removes `node.left = insert(node.left, key)` from the dependency chain described above.
- Without L11: 754 tokens; removes `} else {` from the dependency chain described above.
- Without L12: 743 tokens; removes `node.right = insert(node.right, key)` from the dependency chain described above.
- Without L13: 758 tokens; removes `}` from the dependency chain described above.
- Without L14: 756 tokens; removes `return node` from the dependency chain described above.
- Without L15: 759 tokens; removes `}` from the dependency chain described above.
- Without L17: 733 tokens; removes `func delete(_ node: Node?, _ key: Int) -> Node? {` from the dependency chain described above.
- Without L18: 744 tokens; removes `guard let node else { return nil }` from the dependency chain described above.
- Without L19: 748 tokens; removes `if key < node.key {` from the dependency chain described above.
- Without L20: 743 tokens; removes `node.left = delete(node.left, key)` from the dependency chain described above.
- Without L21: 744 tokens; removes `} else if key > node.key {` from the dependency chain described above.
- Without L22: 743 tokens; removes `node.right = delete(node.right, key)` from the dependency chain described above.
- Without L23: 754 tokens; removes `} else {` from the dependency chain described above.
- Without L24: 739 tokens; removes `if node.left == nil { return node.right }` from the dependency chain described above.
- Without L25: 739 tokens; removes `if node.right == nil { return node.left }` from the dependency chain described above.
- Without L26: 748 tokens; removes `var successor = node.right!` from the dependency chain described above.
- Without L27: 737 tokens; removes `while let left = successor.left { successor = left }` from the dependency chain described above.
- Without L28: 749 tokens; removes `node.key = successor.key` from the dependency chain described above.
- Without L29: 741 tokens; removes `node.right = delete(node.right, successor.key)` from the dependency chain described above.
- Without L30: 758 tokens; removes `}` from the dependency chain described above.
- Without L31: 756 tokens; removes `return node` from the dependency chain described above.
- Without L32: 759 tokens; removes `}` from the dependency chain described above.
- Without L34: 726 tokens; removes `func traverse(_ node: Node?, _ mode: Int, _ order: inout [Int]) {` from the dependency chain described above.
- Without L35: 746 tokens; removes `guard let node else { return }` from the dependency chain described above.
- Without L36: 739 tokens; removes `if mode == 1 { order.append(node.key) }` from the dependency chain described above.
- Without L37: 746 tokens; removes `traverse(node.left, mode, &order)` from the dependency chain described above.
- Without L39: 746 tokens; removes `traverse(node.right, mode, &order)` from the dependency chain described above.
- Without L41: 759 tokens; removes `}` from the dependency chain described above.
- Without L43: 742 tokens; removes `func height(_ node: Node?) -> Int {` from the dependency chain described above.
- Without L44: 744 tokens; removes `guard let node else { return 0 }` from the dependency chain described above.
- Without L45: 736 tokens; removes `return 1 + max(height(node.left), height(node.right))` from the dependency chain described above.
- Without L46: 759 tokens; removes `}` from the dependency chain described above.
- Without L48: 749 tokens; removes `var root: Node? = nil` from the dependency chain described above.
- Without L49: 691 tokens; removes `for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] { root = insert(root, key) }` from the dependency chain described above.
- Without L66: 749 tokens; removes `root = delete(root, 6)` from the dependency chain described above.
- Without L67: 748 tokens; removes `root = delete(root, 27)` from the dependency chain described above.
- Without L68: 749 tokens; removes `var after = [Int]()` from the dependency chain described above.
- Without L69: 749 tokens; removes `traverse(root, 1, &after)` from the dependency chain described above.
- Without L70: 727 tokens; removes `print("preorder after deletions: \(after.map(String.init).joined(separator: " "))")` from the dependency chain described above.
- Without L71: 741 tokens; removes `print("height after deletions: \(height(root))")` from the dependency chain described above.
