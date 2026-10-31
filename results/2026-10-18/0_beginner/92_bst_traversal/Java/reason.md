# Task B selection: 92_bst_traversal / Java

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `Main.java`. Selected original locations: L8,L9,L11,L12,L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L53,L54,L55,L56,L57,L58,L59,L60,L64,L70,L71,L74,L75,L79,L80,L81,L82,L104,L105,L106,L107,L108,L109.

- L8: `        int key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        Node left, right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        Node(int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            this.key = key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    static Node insert(Node node, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        if (node == null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `            return new Node(key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `        if (key < node.key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            node.left = insert(node.left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            node.right = insert(node.right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `        return node;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    static Node delete(Node node, int key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if (node == null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            return null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `        if (key < node.key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            node.left = delete(node.left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        } else if (key > node.key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            node.right = delete(node.right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            if (node.left == null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                return node.right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `            if (node.right == null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                return node.left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `            Node successor = node.right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `            while (successor.left != null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `                successor = successor.left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `            node.key = successor.key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            node.right = delete(node.right, successor.key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `        return node;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    static void traverse(Node node, int mode, List<Integer> order) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        if (node == null) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `            return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `        if (mode == 1) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `            order.add(node.key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L60: `        traverse(node.left, mode, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `        traverse(node.right, mode, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `    static int height(Node node) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `        return node == null ? 0 : 1 + Math.max(height(node.left), height(node.right));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `    static String joined(List<Integer> values) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L75: `        return String.join(" ", values.stream().map(String::valueOf).toList());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `        Node root = null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `        for (int key : new int[]{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `            root = insert(root, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L104: `        root = delete(root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L105: `        root = delete(root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L106: `        List<Integer> after = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L107: `        traverse(root, 1, after);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L108: `        System.out.println("preorder after deletions: " + joined(after));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L109: `        System.out.println("height after deletions: " + height(root));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **900 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 799 tokens. The contiguous original span L8–L109 costs 1344 tokens; the complete original source costs 1405 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 893 tokens; removes `int key;` from the dependency chain described above.
- Without L9: 890 tokens; removes `Node left, right;` from the dependency chain described above.
- Without L11: 889 tokens; removes `Node(int key) {` from the dependency chain described above.
- Without L12: 888 tokens; removes `this.key = key;` from the dependency chain described above.
- Without L13: 896 tokens; removes `}` from the dependency chain described above.
- Without L14: 897 tokens; removes `}` from the dependency chain described above.
- Without L16: 881 tokens; removes `static Node insert(Node node, int key) {` from the dependency chain described above.
- Without L17: 886 tokens; removes `if (node == null) {` from the dependency chain described above.
- Without L18: 887 tokens; removes `return new Node(key);` from the dependency chain described above.
- Without L19: 896 tokens; removes `}` from the dependency chain described above.
- Without L20: 884 tokens; removes `if (key < node.key) {` from the dependency chain described above.
- Without L21: 880 tokens; removes `node.left = insert(node.left, key);` from the dependency chain described above.
- Without L22: 892 tokens; removes `} else {` from the dependency chain described above.
- Without L23: 880 tokens; removes `node.right = insert(node.right, key);` from the dependency chain described above.
- Without L24: 896 tokens; removes `}` from the dependency chain described above.
- Without L25: 893 tokens; removes `return node;` from the dependency chain described above.
- Without L28: 881 tokens; removes `static Node delete(Node node, int key) {` from the dependency chain described above.
- Without L29: 886 tokens; removes `if (node == null) {` from the dependency chain described above.
- Without L30: 892 tokens; removes `return null;` from the dependency chain described above.
- Without L31: 896 tokens; removes `}` from the dependency chain described above.
- Without L32: 884 tokens; removes `if (key < node.key) {` from the dependency chain described above.
- Without L33: 880 tokens; removes `node.left = delete(node.left, key);` from the dependency chain described above.
- Without L34: 880 tokens; removes `} else if (key > node.key) {` from the dependency chain described above.
- Without L35: 880 tokens; removes `node.right = delete(node.right, key);` from the dependency chain described above.
- Without L36: 892 tokens; removes `} else {` from the dependency chain described above.
- Without L37: 883 tokens; removes `if (node.left == null) {` from the dependency chain described above.
- Without L38: 889 tokens; removes `return node.right;` from the dependency chain described above.
- Without L39: 895 tokens; removes `}` from the dependency chain described above.
- Without L40: 883 tokens; removes `if (node.right == null) {` from the dependency chain described above.
- Without L41: 889 tokens; removes `return node.left;` from the dependency chain described above.
- Without L42: 895 tokens; removes `}` from the dependency chain described above.
- Without L43: 886 tokens; removes `Node successor = node.right;` from the dependency chain described above.
- Without L44: 883 tokens; removes `while (successor.left != null) {` from the dependency chain described above.
- Without L45: 887 tokens; removes `successor = successor.left;` from the dependency chain described above.
- Without L46: 895 tokens; removes `}` from the dependency chain described above.
- Without L47: 886 tokens; removes `node.key = successor.key;` from the dependency chain described above.
- Without L48: 878 tokens; removes `node.right = delete(node.right, successor.key);` from the dependency chain described above.
- Without L49: 896 tokens; removes `}` from the dependency chain described above.
- Without L50: 893 tokens; removes `return node;` from the dependency chain described above.
- Without L53: 873 tokens; removes `static void traverse(Node node, int mode, List<Integer> order) {` from the dependency chain described above.
- Without L54: 886 tokens; removes `if (node == null) {` from the dependency chain described above.
- Without L55: 894 tokens; removes `return;` from the dependency chain described above.
- Without L56: 896 tokens; removes `}` from the dependency chain described above.
- Without L57: 886 tokens; removes `if (mode == 1) {` from the dependency chain described above.
- Without L58: 887 tokens; removes `order.add(node.key);` from the dependency chain described above.
- Without L59: 896 tokens; removes `}` from the dependency chain described above.
- Without L60: 884 tokens; removes `traverse(node.left, mode, order);` from the dependency chain described above.
- Without L64: 884 tokens; removes `traverse(node.right, mode, order);` from the dependency chain described above.
- Without L70: 886 tokens; removes `static int height(Node node) {` from the dependency chain described above.
- Without L71: 859 tokens; removes `return node == null ? 0 : 1 + Math.max(height(node.left), height(node.right));` from the dependency chain described above.
- Without L74: 883 tokens; removes `static String joined(List<Integer> values) {` from the dependency chain described above.
- Without L75: 866 tokens; removes `return String.join(" ", values.stream().map(String::valueOf).toList());` from the dependency chain described above.
- Without L79: 889 tokens; removes `Node root = null;` from the dependency chain described above.
- Without L80: 834 tokens; removes `for (int key : new int[]{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}) {` from the dependency chain described above.
- Without L81: 884 tokens; removes `root = insert(root, key);` from the dependency chain described above.
- Without L82: 896 tokens; removes `}` from the dependency chain described above.
- Without L104: 885 tokens; removes `root = delete(root, 6);` from the dependency chain described above.
- Without L105: 884 tokens; removes `root = delete(root, 27);` from the dependency chain described above.
- Without L106: 879 tokens; removes `List<Integer> after = new ArrayList<>();` from the dependency chain described above.
- Without L107: 886 tokens; removes `traverse(root, 1, after);` from the dependency chain described above.
- Without L108: 873 tokens; removes `System.out.println("preorder after deletions: " + joined(after));` from the dependency chain described above.
- Without L109: 873 tokens; removes `System.out.println("height after deletions: " + height(root));` from the dependency chain described above.
