# Task B selection: 92_bst_traversal / Go

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.go`. Selected original locations: L6,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L24,L25,L26,L27,L28,L29,L30,L31,L35,L41,L42,L43,L44,L45,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L75,L76,L77,L78,L97,L98,L99,L100,L101.

- L6: `	key, left, right int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `func insert(nodes *[]Node, root, key int) int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `	if root < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `		*nodes = append(*nodes, Node{key, -1, -1})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `		return len(*nodes) - 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `	if key < (*nodes)[root].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `		child := insert(nodes, (*nodes)[root].left, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `		(*nodes)[root].left = child` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `	} else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `		child := insert(nodes, (*nodes)[root].right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `		(*nodes)[root].right = child` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `	return root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `func traverse(nodes []Node, root, mode int) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `	if root < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `		return` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `	if mode == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `		fmt.Printf(" %d", nodes[root].key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `	traverse(nodes, nodes[root].left, mode)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `	traverse(nodes, nodes[root].right, mode)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `func height(nodes []Node, root int) int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `	if root < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `		return 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `	return 1 + max(height(nodes, nodes[root].left), height(nodes, nodes[root].right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `func erase(nodes []Node, root, key int) int {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `	if root < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `		return root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `	if key < nodes[root].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `		nodes[root].left = erase(nodes, nodes[root].left, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `	} else if key > nodes[root].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `		nodes[root].right = erase(nodes, nodes[root].right, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `	} else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `		if nodes[root].left < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `			return nodes[root].right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L60: `		if nodes[root].right < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `			return nodes[root].left` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L63: `		successor := nodes[root].right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `		for nodes[successor].left >= 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `			successor = nodes[successor].left` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L67: `		nodes[root].key = nodes[successor].key` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `		nodes[root].right = erase(nodes, nodes[root].right, nodes[successor].key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L70: `	return root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L75: `	root := -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L76: `	for _, key := range []int{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34} {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L77: `		root = insert(&nodes, root, key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L97: `	root = erase(nodes, root, 6)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L98: `	root = erase(nodes, root, 27)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L99: `	fmt.Print("preorder after deletions:")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L100: `	traverse(nodes, root, 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L101: `	fmt.Printf("\nheight after deletions: %d\n", height(nodes, root))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **854 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 818 tokens. The contiguous original span L6–L101 costs 1211 tokens; the complete original source costs 1233 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 843 tokens; removes `key, left, right int` from the dependency chain described above.
- Without L9: 831 tokens; removes `func insert(nodes *[]Node, root, key int) int {` from the dependency chain described above.
- Without L10: 843 tokens; removes `if root < 0 {` from the dependency chain described above.
- Without L11: 827 tokens; removes `*nodes = append(*nodes, Node{key, -1, -1})` from the dependency chain described above.
- Without L12: 840 tokens; removes `return len(*nodes) - 1` from the dependency chain described above.
- Without L13: 851 tokens; removes `}` from the dependency chain described above.
- Without L14: 836 tokens; removes `if key < (*nodes)[root].key {` from the dependency chain described above.
- Without L15: 830 tokens; removes `child := insert(nodes, (*nodes)[root].left, key)` from the dependency chain described above.
- Without L16: 839 tokens; removes `(*nodes)[root].left = child` from the dependency chain described above.
- Without L17: 847 tokens; removes `} else {` from the dependency chain described above.
- Without L18: 830 tokens; removes `child := insert(nodes, (*nodes)[root].right, key)` from the dependency chain described above.
- Without L19: 839 tokens; removes `(*nodes)[root].right = child` from the dependency chain described above.
- Without L20: 851 tokens; removes `}` from the dependency chain described above.
- Without L21: 849 tokens; removes `return root` from the dependency chain described above.
- Without L24: 834 tokens; removes `func traverse(nodes []Node, root, mode int) {` from the dependency chain described above.
- Without L25: 843 tokens; removes `if root < 0 {` from the dependency chain described above.
- Without L26: 850 tokens; removes `return` from the dependency chain described above.
- Without L27: 851 tokens; removes `}` from the dependency chain described above.
- Without L28: 843 tokens; removes `if mode == 1 {` from the dependency chain described above.
- Without L29: 834 tokens; removes `fmt.Printf(" %d", nodes[root].key)` from the dependency chain described above.
- Without L30: 851 tokens; removes `}` from the dependency chain described above.
- Without L31: 838 tokens; removes `traverse(nodes, nodes[root].left, mode)` from the dependency chain described above.
- Without L35: 838 tokens; removes `traverse(nodes, nodes[root].right, mode)` from the dependency chain described above.
- Without L41: 835 tokens; removes `func height(nodes []Node, root int) int {` from the dependency chain described above.
- Without L42: 843 tokens; removes `if root < 0 {` from the dependency chain described above.
- Without L43: 848 tokens; removes `return 0` from the dependency chain described above.
- Without L44: 851 tokens; removes `}` from the dependency chain described above.
- Without L45: 819 tokens; removes `return 1 + max(height(nodes, nodes[root].left), height(nodes, nodes[root].right))` from the dependency chain described above.
- Without L48: 832 tokens; removes `func erase(nodes []Node, root, key int) int {` from the dependency chain described above.
- Without L49: 843 tokens; removes `if root < 0 {` from the dependency chain described above.
- Without L50: 848 tokens; removes `return root` from the dependency chain described above.
- Without L51: 851 tokens; removes `}` from the dependency chain described above.
- Without L52: 839 tokens; removes `if key < nodes[root].key {` from the dependency chain described above.
- Without L53: 829 tokens; removes `nodes[root].left = erase(nodes, nodes[root].left, key)` from the dependency chain described above.
- Without L54: 835 tokens; removes `} else if key > nodes[root].key {` from the dependency chain described above.
- Without L55: 829 tokens; removes `nodes[root].right = erase(nodes, nodes[root].right, key)` from the dependency chain described above.
- Without L56: 847 tokens; removes `} else {` from the dependency chain described above.
- Without L57: 838 tokens; removes `if nodes[root].left < 0 {` from the dependency chain described above.
- Without L58: 843 tokens; removes `return nodes[root].right` from the dependency chain described above.
- Without L59: 850 tokens; removes `}` from the dependency chain described above.
- Without L60: 838 tokens; removes `if nodes[root].right < 0 {` from the dependency chain described above.
- Without L61: 843 tokens; removes `return nodes[root].left` from the dependency chain described above.
- Without L62: 850 tokens; removes `}` from the dependency chain described above.
- Without L63: 842 tokens; removes `successor := nodes[root].right` from the dependency chain described above.
- Without L64: 838 tokens; removes `for nodes[successor].left >= 0 {` from the dependency chain described above.
- Without L65: 841 tokens; removes `successor = nodes[successor].left` from the dependency chain described above.
- Without L66: 850 tokens; removes `}` from the dependency chain described above.
- Without L67: 838 tokens; removes `nodes[root].key = nodes[successor].key` from the dependency chain described above.
- Without L68: 825 tokens; removes `nodes[root].right = erase(nodes, nodes[root].right, nodes[successor].key)` from the dependency chain described above.
- Without L69: 851 tokens; removes `}` from the dependency chain described above.
- Without L70: 849 tokens; removes `return root` from the dependency chain described above.
- Without L75: 846 tokens; removes `root := -1` from the dependency chain described above.
- Without L76: 790 tokens; removes `for _, key := range []int{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34} {` from the dependency chain described above.
- Without L77: 836 tokens; removes `root = insert(&nodes, root, key)` from the dependency chain described above.
- Without L78: 851 tokens; removes `}` from the dependency chain described above.
- Without L97: 838 tokens; removes `root = erase(nodes, root, 6)` from the dependency chain described above.
- Without L98: 837 tokens; removes `root = erase(nodes, root, 27)` from the dependency chain described above.
- Without L99: 839 tokens; removes `fmt.Print("preorder after deletions:")` from the dependency chain described above.
- Without L100: 842 tokens; removes `traverse(nodes, root, 1)` from the dependency chain described above.
- Without L101: 824 tokens; removes `fmt.Printf("\nheight after deletions: %d\n", height(nodes, root))` from the dependency chain described above.
