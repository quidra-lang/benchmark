# Task B selection: 92_bst_traversal / C#

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

End the named insertion/deletion/traversal helper before the following helper or top-level construction/output. These languages permit nested/local functions, so the explicit scope boundary establishes the selected caller/helper relationship rather than relying on indentation.

Source: `Program.cs`. Selected original locations: L7,L8,L9,L10,L11,L12,L13,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L38,L39,L40,L41,L42,L44,L46,L48,L50,L51,L71,L72,L73,L74,L75,L76,L78,L79,L80,L81.

- L7: `static Node Insert(Node? node, int key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `    if (node is null) return new Node(key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    if (key < node.Key) node.Left = Insert(node.Left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    else node.Right = Insert(node.Right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    return node;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `static Node? Delete(Node? node, int key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    if (node is null) return null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    if (key < node.Key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `        node.Left = Delete(node.Left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    else if (key > node.Key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `        node.Right = Delete(node.Right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `        if (node.Left is null) return node.Right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if (node.Right is null) return node.Left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        Node successor = node.Right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        while (successor.Left is not null) successor = successor.Left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        node.Key = successor.Key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        node.Right = Delete(node.Right, successor.Key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    return node;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `static void Traverse(Node? node, int mode, List<int> order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `    if (node is null) return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    if (mode == 1) order.Add(node.Key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    Traverse(node.Left, mode, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    Traverse(node.Right, mode, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `static int Height(Node? node) => node is null ? 0 : 1 + Math.Max(Height(node.Left), Height(node.Right));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `Node? root = null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `foreach (int key in new[] { 50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34 }) root = Insert(root, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `root = Delete(root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `root = Delete(root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `var after = new List<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `Traverse(root, 1, after);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L75: `Console.WriteLine($"preorder after deletions: {string.Join(" ", after)}");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L76: `Console.WriteLine($"height after deletions: {Height(root)}");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `class Node(int key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L80: `    public int Key = key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `    public Node? Left, Right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **719 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 717 tokens. The contiguous original span L7–L81 costs 1060 tokens; the complete original source costs 1100 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 702 tokens; removes `static Node Insert(Node? node, int key)` from the dependency chain described above.
- Without L8: 717 tokens; removes `{` from the dependency chain described above.
- Without L9: 698 tokens; removes `if (node is null) return new Node(key);` from the dependency chain described above.
- Without L10: 689 tokens; removes `if (key < node.Key) node.Left = Insert(node.Left, key);` from the dependency chain described above.
- Without L11: 699 tokens; removes `else node.Right = Insert(node.Right, key);` from the dependency chain described above.
- Without L12: 713 tokens; removes `return node;` from the dependency chain described above.
- Without L13: 717 tokens; removes `}` from the dependency chain described above.
- Without L15: 701 tokens; removes `static Node? Delete(Node? node, int key)` from the dependency chain described above.
- Without L16: 717 tokens; removes `{` from the dependency chain described above.
- Without L17: 703 tokens; removes `if (node is null) return null;` from the dependency chain described above.
- Without L18: 706 tokens; removes `if (key < node.Key)` from the dependency chain described above.
- Without L19: 716 tokens; removes `{` from the dependency chain described above.
- Without L20: 700 tokens; removes `node.Left = Delete(node.Left, key);` from the dependency chain described above.
- Without L21: 716 tokens; removes `}` from the dependency chain described above.
- Without L22: 704 tokens; removes `else if (key > node.Key)` from the dependency chain described above.
- Without L23: 716 tokens; removes `{` from the dependency chain described above.
- Without L24: 700 tokens; removes `node.Right = Delete(node.Right, key);` from the dependency chain described above.
- Without L25: 716 tokens; removes `}` from the dependency chain described above.
- Without L26: 716 tokens; removes `else` from the dependency chain described above.
- Without L27: 716 tokens; removes `{` from the dependency chain described above.
- Without L28: 698 tokens; removes `if (node.Left is null) return node.Right;` from the dependency chain described above.
- Without L29: 698 tokens; removes `if (node.Right is null) return node.Left;` from the dependency chain described above.
- Without L30: 706 tokens; removes `Node successor = node.Right;` from the dependency chain described above.
- Without L31: 694 tokens; removes `while (successor.Left is not null) successor = successor.Left;` from the dependency chain described above.
- Without L32: 706 tokens; removes `node.Key = successor.Key;` from the dependency chain described above.
- Without L33: 698 tokens; removes `node.Right = Delete(node.Right, successor.Key);` from the dependency chain described above.
- Without L34: 716 tokens; removes `}` from the dependency chain described above.
- Without L35: 713 tokens; removes `return node;` from the dependency chain described above.
- Without L36: 717 tokens; removes `}` from the dependency chain described above.
- Without L38: 694 tokens; removes `static void Traverse(Node? node, int mode, List<int> order)` from the dependency chain described above.
- Without L39: 717 tokens; removes `{` from the dependency chain described above.
- Without L40: 705 tokens; removes `if (node is null) return;` from the dependency chain described above.
- Without L41: 698 tokens; removes `if (mode == 1) order.Add(node.Key);` from the dependency chain described above.
- Without L42: 704 tokens; removes `Traverse(node.Left, mode, order);` from the dependency chain described above.
- Without L44: 704 tokens; removes `Traverse(node.Right, mode, order);` from the dependency chain described above.
- Without L46: 717 tokens; removes `}` from the dependency chain described above.
- Without L48: 668 tokens; removes `static int Height(Node? node) => node is null ? 0 : 1 + Math.Max(Height(node.Left), Height(node.Right));` from the dependency chain described above.
- Without L50: 709 tokens; removes `Node? root = null;` from the dependency chain described above.
- Without L51: 643 tokens; removes `foreach (int key in new[] { 50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34 }) root = Insert(root, key);` from the dependency chain described above.
- Without L71: 706 tokens; removes `root = Delete(root, 6);` from the dependency chain described above.
- Without L72: 705 tokens; removes `root = Delete(root, 27);` from the dependency chain described above.
- Without L73: 703 tokens; removes `var after = new List<int>();` from the dependency chain described above.
- Without L74: 707 tokens; removes `Traverse(root, 1, after);` from the dependency chain described above.
- Without L75: 688 tokens; removes `Console.WriteLine($"preorder after deletions: {string.Join(" ", after)}");` from the dependency chain described above.
- Without L76: 695 tokens; removes `Console.WriteLine($"height after deletions: {Height(root)}");` from the dependency chain described above.
- Without L78: 710 tokens; removes `class Node(int key)` from the dependency chain described above.
- Without L79: 717 tokens; removes `{` from the dependency chain described above.
- Without L80: 707 tokens; removes `public int Key = key;` from the dependency chain described above.
- Without L81: 707 tokens; removes `public Node? Left, Right;` from the dependency chain described above.
