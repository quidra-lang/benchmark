# Task B selection: 92_bst_traversal / C

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.c`. Selected original locations: L4,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L23,L24,L25,L26,L27,L28,L31,L36,L37,L38,L39,L40,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L65,L66,L67,L86,L87,L88,L89,L90.

- L4: `    int key, left, right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `int insert(int root, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    if (root < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        int v = used++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        nodes[v] = (Node){key, -1, -1};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        return v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    if (key < nodes[root].key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        nodes[root].left = insert(nodes[root].left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `        nodes[root].right = insert(nodes[root].right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `void traverse(int root, int mode) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    if (root < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    if (mode == 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        printf(" %d", nodes[root].key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    traverse(nodes[root].left, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    traverse(nodes[root].right, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `int height(int root) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    if (root < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        return 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    int l = height(nodes[root].left), r = height(nodes[root].right);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    return 1 + (l > r ? l : r);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `int erase(int root, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    if (root < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    if (key < nodes[root].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        nodes[root].left = erase(nodes[root].left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    } else if (key > nodes[root].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        nodes[root].right = erase(nodes[root].right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        if (nodes[root].left < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `            return nodes[root].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        if (nodes[root].right < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `            return nodes[root].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        int successor = nodes[root].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        while (nodes[successor].left >= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `            successor = nodes[successor].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        nodes[root].key = nodes[successor].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        nodes[root].right = erase(nodes[root].right, nodes[successor].key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L61: `    return root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `    int keys[] = {50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}, root = -1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    for (int i = 0; i < 12; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `        root = insert(root, keys[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L86: `    root = erase(root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `    root = erase(root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L88: `    printf("preorder after deletions:");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L89: `    traverse(root, 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L90: `    printf("\nheight after deletions: %d\n", height(root));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **798 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 792 tokens. The contiguous original span L4–L90 costs 1186 tokens; the complete original source costs 1210 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L4: 786 tokens; removes `int key, left, right;` from the dependency chain described above.
- Without L10: 782 tokens; removes `int insert(int root, int key) {` from the dependency chain described above.
- Without L11: 785 tokens; removes `if (root < 0) {` from the dependency chain described above.
- Without L12: 786 tokens; removes `int v = used++;` from the dependency chain described above.
- Without L13: 773 tokens; removes `nodes[v] = (Node){key, -1, -1};` from the dependency chain described above.
- Without L14: 791 tokens; removes `return v;` from the dependency chain described above.
- Without L15: 795 tokens; removes `}` from the dependency chain described above.
- Without L16: 783 tokens; removes `if (key < nodes[root].key)` from the dependency chain described above.
- Without L17: 775 tokens; removes `nodes[root].left = insert(nodes[root].left, key);` from the dependency chain described above.
- Without L18: 795 tokens; removes `else` from the dependency chain described above.
- Without L19: 775 tokens; removes `nodes[root].right = insert(nodes[root].right, key);` from the dependency chain described above.
- Without L20: 792 tokens; removes `return root;` from the dependency chain described above.
- Without L23: 782 tokens; removes `void traverse(int root, int mode) {` from the dependency chain described above.
- Without L24: 787 tokens; removes `if (root < 0)` from the dependency chain described above.
- Without L25: 793 tokens; removes `return;` from the dependency chain described above.
- Without L26: 787 tokens; removes `if (mode == 1)` from the dependency chain described above.
- Without L27: 779 tokens; removes `printf(" %d", nodes[root].key);` from the dependency chain described above.
- Without L28: 784 tokens; removes `traverse(nodes[root].left, mode);` from the dependency chain described above.
- Without L31: 784 tokens; removes `traverse(nodes[root].right, mode);` from the dependency chain described above.
- Without L36: 787 tokens; removes `int height(int root) {` from the dependency chain described above.
- Without L37: 787 tokens; removes `if (root < 0)` from the dependency chain described above.
- Without L38: 791 tokens; removes `return 0;` from the dependency chain described above.
- Without L39: 767 tokens; removes `int l = height(nodes[root].left), r = height(nodes[root].right);` from the dependency chain described above.
- Without L40: 774 tokens; removes `return 1 + (l > r ? l : r);` from the dependency chain described above.
- Without L43: 782 tokens; removes `int erase(int root, int key) {` from the dependency chain described above.
- Without L44: 787 tokens; removes `if (root < 0)` from the dependency chain described above.
- Without L45: 791 tokens; removes `return root;` from the dependency chain described above.
- Without L46: 781 tokens; removes `if (key < nodes[root].key) {` from the dependency chain described above.
- Without L47: 775 tokens; removes `nodes[root].left = erase(nodes[root].left, key);` from the dependency chain described above.
- Without L48: 777 tokens; removes `} else if (key > nodes[root].key) {` from the dependency chain described above.
- Without L49: 775 tokens; removes `nodes[root].right = erase(nodes[root].right, key);` from the dependency chain described above.
- Without L50: 791 tokens; removes `} else {` from the dependency chain described above.
- Without L51: 782 tokens; removes `if (nodes[root].left < 0)` from the dependency chain described above.
- Without L52: 786 tokens; removes `return nodes[root].right;` from the dependency chain described above.
- Without L53: 782 tokens; removes `if (nodes[root].right < 0)` from the dependency chain described above.
- Without L54: 786 tokens; removes `return nodes[root].left;` from the dependency chain described above.
- Without L55: 783 tokens; removes `int successor = nodes[root].right;` from the dependency chain described above.
- Without L56: 782 tokens; removes `while (nodes[successor].left >= 0)` from the dependency chain described above.
- Without L57: 784 tokens; removes `successor = nodes[successor].left;` from the dependency chain described above.
- Without L58: 781 tokens; removes `nodes[root].key = nodes[successor].key;` from the dependency chain described above.
- Without L59: 771 tokens; removes `nodes[root].right = erase(nodes[root].right, nodes[successor].key);` from the dependency chain described above.
- Without L60: 795 tokens; removes `}` from the dependency chain described above.
- Without L61: 792 tokens; removes `return root;` from the dependency chain described above.
- Without L65: 733 tokens; removes `int keys[] = {50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}, root = -1;` from the dependency chain described above.
- Without L66: 773 tokens; removes `for (int i = 0; i < 12; i++)` from the dependency chain described above.
- Without L67: 780 tokens; removes `root = insert(root, keys[i]);` from the dependency chain described above.
- Without L86: 784 tokens; removes `root = erase(root, 6);` from the dependency chain described above.
- Without L87: 783 tokens; removes `root = erase(root, 27);` from the dependency chain described above.
- Without L88: 784 tokens; removes `printf("preorder after deletions:");` from the dependency chain described above.
- Without L89: 788 tokens; removes `traverse(root, 1);` from the dependency chain described above.
- Without L90: 772 tokens; removes `printf("\nheight after deletions: %d\n", height(root));` from the dependency chain described above.
