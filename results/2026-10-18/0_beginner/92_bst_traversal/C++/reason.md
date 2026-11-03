# Task B selection: 92_bst_traversal / C++

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.cpp`. Selected original locations: L8,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28,L29,L30,L31,L32,L33,L36,L41,L42,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L67,L68,L69,L87,L88,L89,L90,L91.

- L8: `    int key, left = -1, right = -1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `int insert(int root, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    if (root < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        nodes.push_back({key});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        return static_cast<int>(nodes.size()) - 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    if (key < nodes[root].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        int child = insert(nodes[root].left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        nodes[root].left = child;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        int child = insert(nodes[root].right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        nodes[root].right = child;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `    return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `void traverse(int root, int mode) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    if (root < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    if (mode == 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        std::cout << ' ' << nodes[root].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    traverse(nodes[root].left, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    traverse(nodes[root].right, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `int height(int root) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    return root < 0 ? 0 : 1 + std::max(height(nodes[root].left), height(nodes[root].right));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `int erase(int root, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    if (root < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    if (key < nodes[root].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        nodes[root].left = erase(nodes[root].left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    } else if (key > nodes[root].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        nodes[root].right = erase(nodes[root].right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        if (nodes[root].left < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `            return nodes[root].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        if (nodes[root].right < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `            return nodes[root].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        int successor = nodes[root].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        while (nodes[successor].left >= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `            successor = nodes[successor].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `        nodes[root].key = nodes[successor].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        nodes[root].right = erase(nodes[root].right, nodes[successor].key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L63: `    return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `    int root = -1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `    for (int key : std::array<int, 12>{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `        root = insert(root, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `    root = erase(root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L88: `    root = erase(root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L89: `    std::cout << "preorder after deletions:";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L90: `    traverse(root, 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L91: `    std::cout << "\nheight after deletions: " << height(root) << '\n';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **802 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 793 tokens. The contiguous original span L8–L91 costs 1206 tokens; the complete original source costs 1250 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 780 tokens; removes `int key, left = -1, right = -1;` from the dependency chain described above.
- Without L13: 786 tokens; removes `int insert(int root, int key) {` from the dependency chain described above.
- Without L14: 789 tokens; removes `if (root < 0) {` from the dependency chain described above.
- Without L15: 788 tokens; removes `nodes.push_back({key});` from the dependency chain described above.
- Without L16: 779 tokens; removes `return static_cast<int>(nodes.size()) - 1;` from the dependency chain described above.
- Without L17: 799 tokens; removes `}` from the dependency chain described above.
- Without L18: 785 tokens; removes `if (key < nodes[root].key) {` from the dependency chain described above.
- Without L19: 781 tokens; removes `int child = insert(nodes[root].left, key);` from the dependency chain described above.
- Without L20: 789 tokens; removes `nodes[root].left = child;` from the dependency chain described above.
- Without L21: 795 tokens; removes `} else {` from the dependency chain described above.
- Without L22: 781 tokens; removes `int child = insert(nodes[root].right, key);` from the dependency chain described above.
- Without L23: 789 tokens; removes `nodes[root].right = child;` from the dependency chain described above.
- Without L24: 799 tokens; removes `}` from the dependency chain described above.
- Without L25: 796 tokens; removes `return root;` from the dependency chain described above.
- Without L28: 786 tokens; removes `void traverse(int root, int mode) {` from the dependency chain described above.
- Without L29: 791 tokens; removes `if (root < 0)` from the dependency chain described above.
- Without L30: 797 tokens; removes `return;` from the dependency chain described above.
- Without L31: 791 tokens; removes `if (mode == 1)` from the dependency chain described above.
- Without L32: 781 tokens; removes `std::cout << ' ' << nodes[root].key;` from the dependency chain described above.
- Without L33: 788 tokens; removes `traverse(nodes[root].left, mode);` from the dependency chain described above.
- Without L36: 788 tokens; removes `traverse(nodes[root].right, mode);` from the dependency chain described above.
- Without L41: 791 tokens; removes `int height(int root) {` from the dependency chain described above.
- Without L42: 758 tokens; removes `return root < 0 ? 0 : 1 + std::max(height(nodes[root].left), height(nodes[root].right));` from the dependency chain described above.
- Without L45: 786 tokens; removes `int erase(int root, int key) {` from the dependency chain described above.
- Without L46: 791 tokens; removes `if (root < 0)` from the dependency chain described above.
- Without L47: 795 tokens; removes `return root;` from the dependency chain described above.
- Without L48: 785 tokens; removes `if (key < nodes[root].key) {` from the dependency chain described above.
- Without L49: 779 tokens; removes `nodes[root].left = erase(nodes[root].left, key);` from the dependency chain described above.
- Without L50: 781 tokens; removes `} else if (key > nodes[root].key) {` from the dependency chain described above.
- Without L51: 779 tokens; removes `nodes[root].right = erase(nodes[root].right, key);` from the dependency chain described above.
- Without L52: 795 tokens; removes `} else {` from the dependency chain described above.
- Without L53: 786 tokens; removes `if (nodes[root].left < 0)` from the dependency chain described above.
- Without L54: 790 tokens; removes `return nodes[root].right;` from the dependency chain described above.
- Without L55: 786 tokens; removes `if (nodes[root].right < 0)` from the dependency chain described above.
- Without L56: 790 tokens; removes `return nodes[root].left;` from the dependency chain described above.
- Without L57: 787 tokens; removes `int successor = nodes[root].right;` from the dependency chain described above.
- Without L58: 786 tokens; removes `while (nodes[successor].left >= 0)` from the dependency chain described above.
- Without L59: 788 tokens; removes `successor = nodes[successor].left;` from the dependency chain described above.
- Without L60: 785 tokens; removes `nodes[root].key = nodes[successor].key;` from the dependency chain described above.
- Without L61: 775 tokens; removes `nodes[root].right = erase(nodes[root].right, nodes[successor].key);` from the dependency chain described above.
- Without L62: 799 tokens; removes `}` from the dependency chain described above.
- Without L63: 796 tokens; removes `return root;` from the dependency chain described above.
- Without L67: 791 tokens; removes `int root = -1;` from the dependency chain described above.
- Without L68: 733 tokens; removes `for (int key : std::array<int, 12>{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34})` from the dependency chain described above.
- Without L69: 787 tokens; removes `root = insert(root, key);` from the dependency chain described above.
- Without L87: 788 tokens; removes `root = erase(root, 6);` from the dependency chain described above.
- Without L88: 787 tokens; removes `root = erase(root, 27);` from the dependency chain described above.
- Without L89: 785 tokens; removes `std::cout << "preorder after deletions:";` from the dependency chain described above.
- Without L90: 792 tokens; removes `traverse(root, 1);` from the dependency chain described above.
- Without L91: 769 tokens; removes `std::cout << "\nheight after deletions: " << height(root) << '\n';` from the dependency chain described above.
