# Task B selection: 92_bst_traversal / Quidra

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.qui`. Selected original locations: L1,L2,L3,L4,L5,L6,L9,L13,L14,L15,L16,L17,L18,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L39,L40,L41,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L78,L79,L80,L81,L82,L83.

- L1: `void visit(int node, int mode, int[] keys, int[] left, int[] right, int[] &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    if node == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        return` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    if mode == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        order = order.append(keys[node])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    visit(left[node], mode, keys, left, right, &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    visit(right[node], mode, keys, left, right, &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `int height(int node, int[] left, int[] right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    if node == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        return 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    int first = height(left[node], left, right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    int second = height(right[node], left, right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    return 1 + (if first > second then first else second)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `int erase(int node, int key, int[] &keys, int[] &left, int[] &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    if node == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        return -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    if key < keys[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        left[node] = erase(left[node], key, &keys, &left, &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    elif key > keys[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        right[node] = erase(right[node], key, &keys, &left, &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `        if left[node] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            return right[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        if right[node] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            return left[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        int successor = right[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        while left[successor] != -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            successor = left[successor]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        keys[node] = keys[successor]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        right[node] = erase(right[node], keys[successor], &keys, &left, &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `void show(string label, int[] order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    string[] fields = [for int key = order[] then key.string()]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    print("{label}: {fields.join(" ")}{NL}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `int[] keys = [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `int[] left = array(12, fill = -1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `int[] right = array(12, fill = -1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `int root = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `for 1 <= int i < 12` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    int node = root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    while true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        if keys[i] < keys[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `            if left[node] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `                left[node] = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `                break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `            node = left[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L56: `            if right[node] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `                right[node] = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `                break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `            node = right[node]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `root = erase(root, 6, &keys, &left, &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `root = erase(root, 27, &keys, &left, &right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `int[] after = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `visit(root, 1, keys, left, right, &after)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `show("preorder after deletions", after)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L83: `print("height after deletions: {height(root, left, right)}{NL}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **951 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 883 tokens. The contiguous original span L1–L83 costs 1254 tokens; the complete original source costs 1254 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 912 tokens; removes `void visit(int node, int mode, int[] keys, int[] left, int[] right, int[] &order)` from the dependency chain described above.
- Without L2: 941 tokens; removes `if node == -1` from the dependency chain described above.
- Without L3: 947 tokens; removes `return` from the dependency chain described above.
- Without L4: 942 tokens; removes `if mode == 1` from the dependency chain described above.
- Without L5: 935 tokens; removes `order = order.append(keys[node])` from the dependency chain described above.
- Without L6: 926 tokens; removes `visit(left[node], mode, keys, left, right, &order)` from the dependency chain described above.
- Without L9: 926 tokens; removes `visit(right[node], mode, keys, left, right, &order)` from the dependency chain described above.
- Without L13: 930 tokens; removes `int height(int node, int[] left, int[] right)` from the dependency chain described above.
- Without L14: 941 tokens; removes `if node == -1` from the dependency chain described above.
- Without L15: 945 tokens; removes `return 0` from the dependency chain described above.
- Without L16: 930 tokens; removes `int first = height(left[node], left, right)` from the dependency chain described above.
- Without L17: 930 tokens; removes `int second = height(right[node], left, right)` from the dependency chain described above.
- Without L18: 926 tokens; removes `return 1 + (if first > second then first else second)` from the dependency chain described above.
- Without L20: 916 tokens; removes `int erase(int node, int key, int[] &keys, int[] &left, int[] &right)` from the dependency chain described above.
- Without L21: 941 tokens; removes `if node == -1` from the dependency chain described above.
- Without L22: 944 tokens; removes `return -1` from the dependency chain described above.
- Without L23: 939 tokens; removes `if key < keys[node]` from the dependency chain described above.
- Without L24: 919 tokens; removes `left[node] = erase(left[node], key, &keys, &left, &right)` from the dependency chain described above.
- Without L25: 939 tokens; removes `elif key > keys[node]` from the dependency chain described above.
- Without L26: 919 tokens; removes `right[node] = erase(right[node], key, &keys, &left, &right)` from the dependency chain described above.
- Without L27: 948 tokens; removes `else` from the dependency chain described above.
- Without L28: 937 tokens; removes `if left[node] == -1` from the dependency chain described above.
- Without L29: 941 tokens; removes `return right[node]` from the dependency chain described above.
- Without L30: 937 tokens; removes `if right[node] == -1` from the dependency chain described above.
- Without L31: 941 tokens; removes `return left[node]` from the dependency chain described above.
- Without L32: 938 tokens; removes `int successor = right[node]` from the dependency chain described above.
- Without L33: 937 tokens; removes `while left[successor] != -1` from the dependency chain described above.
- Without L34: 939 tokens; removes `successor = left[successor]` from the dependency chain described above.
- Without L35: 937 tokens; removes `keys[node] = keys[successor]` from the dependency chain described above.
- Without L36: 916 tokens; removes `right[node] = erase(right[node], keys[successor], &keys, &left, &right)` from the dependency chain described above.
- Without L37: 946 tokens; removes `return node` from the dependency chain described above.
- Without L39: 936 tokens; removes `void show(string label, int[] order)` from the dependency chain described above.
- Without L40: 922 tokens; removes `string[] fields = [for int key = order[] then key.string()]` from the dependency chain described above.
- Without L41: 927 tokens; removes `print("{label}: {fields.join(" ")}{NL}")` from the dependency chain described above.
- Without L43: 896 tokens; removes `int[] keys = [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]` from the dependency chain described above.
- Without L44: 930 tokens; removes `int[] left = array(12, fill = -1)` from the dependency chain described above.
- Without L45: 930 tokens; removes `int[] right = array(12, fill = -1)` from the dependency chain described above.
- Without L46: 943 tokens; removes `int root = 0` from the dependency chain described above.
- Without L47: 936 tokens; removes `for 1 <= int i < 12` from the dependency chain described above.
- Without L48: 942 tokens; removes `int node = root` from the dependency chain described above.
- Without L49: 946 tokens; removes `while true` from the dependency chain described above.
- Without L50: 935 tokens; removes `if keys[i] < keys[node]` from the dependency chain described above.
- Without L51: 936 tokens; removes `if left[node] == -1` from the dependency chain described above.
- Without L52: 938 tokens; removes `left[node] = i` from the dependency chain described above.
- Without L53: 945 tokens; removes `break` from the dependency chain described above.
- Without L54: 939 tokens; removes `node = left[node]` from the dependency chain described above.
- Without L55: 947 tokens; removes `else` from the dependency chain described above.
- Without L56: 936 tokens; removes `if right[node] == -1` from the dependency chain described above.
- Without L57: 938 tokens; removes `right[node] = i` from the dependency chain described above.
- Without L58: 945 tokens; removes `break` from the dependency chain described above.
- Without L59: 939 tokens; removes `node = right[node]` from the dependency chain described above.
- Without L78: 927 tokens; removes `root = erase(root, 6, &keys, &left, &right)` from the dependency chain described above.
- Without L79: 926 tokens; removes `root = erase(root, 27, &keys, &left, &right)` from the dependency chain described above.
- Without L80: 942 tokens; removes `int[] after = []` from the dependency chain described above.
- Without L81: 930 tokens; removes `visit(root, 1, keys, left, right, &after)` from the dependency chain described above.
- Without L82: 937 tokens; removes `show("preorder after deletions", after)` from the dependency chain described above.
- Without L83: 923 tokens; removes `print("height after deletions: {height(root, left, right)}{NL}")` from the dependency chain described above.
