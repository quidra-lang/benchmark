# Task B selection: 92_bst_traversal / Lua

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L30,L31,L32,L33,L35,L37,L39,L40,L41,L42,L44,L45,L60,L61,L62,L63,L64,L65.

- L1: `local function insert_node(node, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    if not node then return {value = value} end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    if value < node.value then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        node.left = insert_node(node.left, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `        node.right = insert_node(node.right, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `local function delete_node(node, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    if not node then return nil end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    if value < node.value then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        node.left = delete_node(node.left, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    elseif value > node.value then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        node.right = delete_node(node.right, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    elseif not node.left then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        return node.right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    elseif not node.right then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        return node.left` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `        local successor = node.right` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        while successor.left do successor = successor.left end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        node.value = successor.value` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        node.right = delete_node(node.right, successor.value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    return node` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `local function traversal(node, mode, result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    if not node then return end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    if mode == "preorder" then result[#result + 1] = node.value end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    traversal(node.left, mode, result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    traversal(node.right, mode, result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `local function height(node)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    if not node then return 0 end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    return 1 + math.max(height(node.left), height(node.right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `local tree` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `for _, value in ipairs({50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}) do tree = insert_node(tree, value) end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `tree = delete_node(tree, 6)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `tree = delete_node(tree, 27)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `local result = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `traversal(tree, "preorder", result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `io.write(string.format("preorder after deletions: %s\nheight after deletions: %d\n",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `    table.concat(result, " "), height(tree)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **642 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 628 tokens. The contiguous original span L1–L65 costs 970 tokens; the complete original source costs 970 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 628 tokens; removes `local function insert_node(node, value)` from the dependency chain described above.
- Without L2: 621 tokens; removes `if not node then return {value = value} end` from the dependency chain described above.
- Without L3: 629 tokens; removes `if value < node.value then` from the dependency chain described above.
- Without L4: 622 tokens; removes `node.left = insert_node(node.left, value)` from the dependency chain described above.
- Without L5: 639 tokens; removes `else` from the dependency chain described above.
- Without L6: 622 tokens; removes `node.right = insert_node(node.right, value)` from the dependency chain described above.
- Without L7: 639 tokens; removes `end` from the dependency chain described above.
- Without L8: 637 tokens; removes `return node` from the dependency chain described above.
- Without L9: 640 tokens; removes `end` from the dependency chain described above.
- Without L11: 628 tokens; removes `local function delete_node(node, value)` from the dependency chain described above.
- Without L12: 627 tokens; removes `if not node then return nil end` from the dependency chain described above.
- Without L13: 629 tokens; removes `if value < node.value then` from the dependency chain described above.
- Without L14: 622 tokens; removes `node.left = delete_node(node.left, value)` from the dependency chain described above.
- Without L15: 629 tokens; removes `elseif value > node.value then` from the dependency chain described above.
- Without L16: 622 tokens; removes `node.right = delete_node(node.right, value)` from the dependency chain described above.
- Without L17: 631 tokens; removes `elseif not node.left then` from the dependency chain described above.
- Without L18: 634 tokens; removes `return node.right` from the dependency chain described above.
- Without L19: 631 tokens; removes `elseif not node.right then` from the dependency chain described above.
- Without L20: 634 tokens; removes `return node.left` from the dependency chain described above.
- Without L21: 639 tokens; removes `else` from the dependency chain described above.
- Without L22: 630 tokens; removes `local successor = node.right` from the dependency chain described above.
- Without L23: 622 tokens; removes `while successor.left do successor = successor.left end` from the dependency chain described above.
- Without L24: 630 tokens; removes `node.value = successor.value` from the dependency chain described above.
- Without L25: 620 tokens; removes `node.right = delete_node(node.right, successor.value)` from the dependency chain described above.
- Without L26: 639 tokens; removes `end` from the dependency chain described above.
- Without L27: 637 tokens; removes `return node` from the dependency chain described above.
- Without L28: 640 tokens; removes `end` from the dependency chain described above.
- Without L30: 627 tokens; removes `local function traversal(node, mode, result)` from the dependency chain described above.
- Without L31: 629 tokens; removes `if not node then return end` from the dependency chain described above.
- Without L32: 611 tokens; removes `if mode == "preorder" then result[#result + 1] = node.value end` from the dependency chain described above.
- Without L33: 628 tokens; removes `traversal(node.left, mode, result)` from the dependency chain described above.
- Without L35: 628 tokens; removes `traversal(node.right, mode, result)` from the dependency chain described above.
- Without L37: 640 tokens; removes `end` from the dependency chain described above.
- Without L39: 633 tokens; removes `local function height(node)` from the dependency chain described above.
- Without L40: 627 tokens; removes `if not node then return 0 end` from the dependency chain described above.
- Without L41: 615 tokens; removes `return 1 + math.max(height(node.left), height(node.right))` from the dependency chain described above.
- Without L42: 640 tokens; removes `end` from the dependency chain described above.
- Without L44: 638 tokens; removes `local tree` from the dependency chain described above.
- Without L45: 564 tokens; removes `for _, value in ipairs({50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}) do tree = insert_node(tree, value) end` from the dependency chain described above.
- Without L60: 628 tokens; removes `tree = delete_node(tree, 6)` from the dependency chain described above.
- Without L61: 627 tokens; removes `tree = delete_node(tree, 27)` from the dependency chain described above.
- Without L62: 633 tokens; removes `local result = {}` from the dependency chain described above.
- Without L63: 629 tokens; removes `traversal(tree, "preorder", result)` from the dependency chain described above.
- Without L64: 609 tokens; removes `io.write(string.format("preorder after deletions: %s\nheight after deletions: %d\n",` from the dependency chain described above.
- Without L65: 621 tokens; removes `table.concat(result, " "), height(tree)))` from the dependency chain described above.
