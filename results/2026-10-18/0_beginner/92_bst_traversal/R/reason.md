# Task B selection: 92_bst_traversal / R

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.R`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L34,L35,L36,L37,L38,L39,L40,L42,L44,L45,L47,L49,L50,L65,L66,L67,L68,L69.

- L1: `insert_node <- function(node, value) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  if (is.null(node)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    return(list(value = value, left = NULL, right = NULL))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `  if (value < node$value) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    node$left <- insert_node(node$left, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    node$right <- insert_node(node$right, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `  node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `delete_node <- function(node, value) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  if (is.null(node)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    return(NULL)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `  if (value < node$value) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    node$left <- delete_node(node$left, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  } else if (value > node$value) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    node$right <- delete_node(node$right, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  } else if (is.null(node$left)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    return(node$right)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  } else if (is.null(node$right)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    return(node$left)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    successor <- node$right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    while (!is.null(successor$left)) successor <- successor$left` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    node$value <- successor$value` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    node$right <- delete_node(node$right, successor$value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `  node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `traversal <- function(node, mode) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  if (is.null(node)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    return(integer(0))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `  left <- traversal(node$left, mode)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `  right <- traversal(node$right, mode)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `  switch(mode,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    preorder = c(node$value, left, right),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `  )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `tree_height <- function(node) if (is.null(node)) 0 else 1 + max(tree_height(node$left), tree_height(node$right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `tree <- NULL` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `for (value in c(50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34)) tree <- insert_node(tree, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `tree <- delete_node(tree, 6)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `tree <- delete_node(tree, 27)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `cat(sprintf(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `  "preorder after deletions: %s\nheight after deletions: %d\n",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `  paste(traversal(tree, "preorder"), collapse = " "), tree_height(tree)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **694 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 670 tokens. The contiguous original span L1–L69 costs 1009 tokens; the complete original source costs 1012 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 678 tokens; removes `insert_node <- function(node, value) {` from the dependency chain described above.
- Without L2: 680 tokens; removes `if (is.null(node)) {` from the dependency chain described above.
- Without L3: 667 tokens; removes `return(list(value = value, left = NULL, right = NULL))` from the dependency chain described above.
- Without L4: 691 tokens; removes `}` from the dependency chain described above.
- Without L5: 679 tokens; removes `if (value < node$value) {` from the dependency chain described above.
- Without L6: 675 tokens; removes `node$left <- insert_node(node$left, value)` from the dependency chain described above.
- Without L7: 687 tokens; removes `} else {` from the dependency chain described above.
- Without L8: 675 tokens; removes `node$right <- insert_node(node$right, value)` from the dependency chain described above.
- Without L9: 691 tokens; removes `}` from the dependency chain described above.
- Without L10: 691 tokens; removes `node` from the dependency chain described above.
- Without L11: 692 tokens; removes `}` from the dependency chain described above.
- Without L13: 678 tokens; removes `delete_node <- function(node, value) {` from the dependency chain described above.
- Without L14: 680 tokens; removes `if (is.null(node)) {` from the dependency chain described above.
- Without L15: 688 tokens; removes `return(NULL)` from the dependency chain described above.
- Without L16: 691 tokens; removes `}` from the dependency chain described above.
- Without L17: 679 tokens; removes `if (value < node$value) {` from the dependency chain described above.
- Without L18: 675 tokens; removes `node$left <- delete_node(node$left, value)` from the dependency chain described above.
- Without L19: 675 tokens; removes `} else if (value > node$value) {` from the dependency chain described above.
- Without L20: 675 tokens; removes `node$right <- delete_node(node$right, value)` from the dependency chain described above.
- Without L21: 674 tokens; removes `} else if (is.null(node$left)) {` from the dependency chain described above.
- Without L22: 686 tokens; removes `return(node$right)` from the dependency chain described above.
- Without L23: 674 tokens; removes `} else if (is.null(node$right)) {` from the dependency chain described above.
- Without L24: 686 tokens; removes `return(node$left)` from the dependency chain described above.
- Without L25: 687 tokens; removes `} else {` from the dependency chain described above.
- Without L26: 685 tokens; removes `successor <- node$right` from the dependency chain described above.
- Without L27: 671 tokens; removes `while (!is.null(successor$left)) successor <- successor$left` from the dependency chain described above.
- Without L28: 683 tokens; removes `node$value <- successor$value` from the dependency chain described above.
- Without L29: 673 tokens; removes `node$right <- delete_node(node$right, successor$value)` from the dependency chain described above.
- Without L30: 691 tokens; removes `}` from the dependency chain described above.
- Without L31: 691 tokens; removes `node` from the dependency chain described above.
- Without L32: 692 tokens; removes `}` from the dependency chain described above.
- Without L34: 680 tokens; removes `traversal <- function(node, mode) {` from the dependency chain described above.
- Without L35: 680 tokens; removes `if (is.null(node)) {` from the dependency chain described above.
- Without L36: 685 tokens; removes `return(integer(0))` from the dependency chain described above.
- Without L37: 691 tokens; removes `}` from the dependency chain described above.
- Without L38: 679 tokens; removes `left <- traversal(node$left, mode)` from the dependency chain described above.
- Without L39: 679 tokens; removes `right <- traversal(node$right, mode)` from the dependency chain described above.
- Without L40: 688 tokens; removes `switch(mode,` from the dependency chain described above.
- Without L42: 675 tokens; removes `preorder = c(node$value, left, right),` from the dependency chain described above.
- Without L44: 691 tokens; removes `)` from the dependency chain described above.
- Without L45: 692 tokens; removes `}` from the dependency chain described above.
- Without L47: 642 tokens; removes `tree_height <- function(node) if (is.null(node)) 0 else 1 + max(tree_height(node$left), tree_height(node$right))` from the dependency chain described above.
- Without L49: 688 tokens; removes `tree <- NULL` from the dependency chain described above.
- Without L50: 623 tokens; removes `for (value in c(50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34)) tree <- insert_node(tree, value)` from the dependency chain described above.
- Without L65: 680 tokens; removes `tree <- delete_node(tree, 6)` from the dependency chain described above.
- Without L66: 679 tokens; removes `tree <- delete_node(tree, 27)` from the dependency chain described above.
- Without L67: 689 tokens; removes `cat(sprintf(` from the dependency chain described above.
- Without L68: 668 tokens; removes `"preorder after deletions: %s\nheight after deletions: %d\n",` from the dependency chain described above.
- Without L69: 663 tokens; removes `paste(traversal(tree, "preorder"), collapse = " "), tree_height(tree)` from the dependency chain described above.
