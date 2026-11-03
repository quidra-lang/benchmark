# Task B selection: 92_bst_traversal / Rust

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.rs`. Selected original locations: L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28,L29,L30,L31,L32,L33,L37,L41,L42,L44,L45,L46,L47,L48,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71,L72,L73,L74,L79,L80,L81,L82,L100,L101,L102,L103,L104.

- L7: `fn insert(nodes: &mut Vec<Node>, root: Option<usize>, key: i32) -> usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    let Some(v) = root else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        nodes.push(Node {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `            key,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `            left: None,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            right: None,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        return nodes.len() - 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    if key < nodes[v].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        let left = nodes[v].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        let child = insert(nodes, left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        nodes[v].left = Some(child);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        let right = nodes[v].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        let child = insert(nodes, right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        nodes[v].right = Some(child);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `    v` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `fn traverse(nodes: &[Node], root: Option<usize>, mode: usize) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    if let Some(v) = root {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        if mode == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            print!(" {}", nodes[v].key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `        traverse(nodes, nodes[v].left, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        traverse(nodes, nodes[v].right, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `fn height(nodes: &[Node], root: Option<usize>) -> usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    root.map_or(0, |v| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        1 + height(nodes, nodes[v].left).max(height(nodes, nodes[v].right))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    })` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `fn erase(nodes: &mut [Node], root: Option<usize>, key: i32) -> Option<usize> {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    let v = root?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    if key < nodes[v].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        let left = nodes[v].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        nodes[v].left = erase(nodes, left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    } else if key > nodes[v].key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        let right = nodes[v].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        nodes[v].right = erase(nodes, right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        if nodes[v].left.is_none() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `            return nodes[v].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L62: `        if nodes[v].right.is_none() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `            return nodes[v].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L65: `        let mut successor = nodes[v].right.unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `        while let Some(left) = nodes[successor].left {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `            successor = left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L69: `        nodes[v].key = nodes[successor].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `        let right = nodes[v].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `        let successor_key = nodes[successor].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `        nodes[v].right = erase(nodes, right, successor_key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L74: `    Some(v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `    let mut root = None;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `    for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `        root = Some(insert(&mut nodes, root, key));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L100: `    root = erase(&mut nodes, root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L101: `    root = erase(&mut nodes, root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L102: `    print!("preorder after deletions:");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L103: `    traverse(&nodes, root, 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L104: `    println!("\nheight after deletions: {}", height(&nodes, root));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1015 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 969 tokens. The contiguous original span L7–L104 costs 1384 tokens; the complete original source costs 1422 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 978 tokens; removes `fn insert(nodes: &mut Vec<Node>, root: Option<usize>, key: i32) -> usize {` from the dependency chain described above.
- Without L8: 999 tokens; removes `let Some(v) = root else {` from the dependency chain described above.
- Without L9: 1005 tokens; removes `nodes.push(Node {` from the dependency chain described above.
- Without L10: 1009 tokens; removes `key,` from the dependency chain described above.
- Without L11: 1006 tokens; removes `left: None,` from the dependency chain described above.
- Without L12: 1006 tokens; removes `right: None,` from the dependency chain described above.
- Without L13: 1009 tokens; removes `});` from the dependency chain described above.
- Without L14: 1000 tokens; removes `return nodes.len() - 1;` from the dependency chain described above.
- Without L15: 1011 tokens; removes `};` from the dependency chain described above.
- Without L16: 1000 tokens; removes `if key < nodes[v].key {` from the dependency chain described above.
- Without L17: 1000 tokens; removes `let left = nodes[v].left;` from the dependency chain described above.
- Without L18: 995 tokens; removes `let child = insert(nodes, left, key);` from the dependency chain described above.
- Without L19: 999 tokens; removes `nodes[v].left = Some(child);` from the dependency chain described above.
- Without L20: 1008 tokens; removes `} else {` from the dependency chain described above.
- Without L21: 1000 tokens; removes `let right = nodes[v].right;` from the dependency chain described above.
- Without L22: 995 tokens; removes `let child = insert(nodes, right, key);` from the dependency chain described above.
- Without L23: 999 tokens; removes `nodes[v].right = Some(child);` from the dependency chain described above.
- Without L24: 1012 tokens; removes `}` from the dependency chain described above.
- Without L25: 1012 tokens; removes `v` from the dependency chain described above.
- Without L28: 985 tokens; removes `fn traverse(nodes: &[Node], root: Option<usize>, mode: usize) {` from the dependency chain described above.
- Without L29: 999 tokens; removes `if let Some(v) = root {` from the dependency chain described above.
- Without L30: 1003 tokens; removes `if mode == 1 {` from the dependency chain described above.
- Without L31: 994 tokens; removes `print!(" {}", nodes[v].key);` from the dependency chain described above.
- Without L32: 1011 tokens; removes `}` from the dependency chain described above.
- Without L33: 997 tokens; removes `traverse(nodes, nodes[v].left, mode);` from the dependency chain described above.
- Without L37: 997 tokens; removes `traverse(nodes, nodes[v].right, mode);` from the dependency chain described above.
- Without L41: 1012 tokens; removes `}` from the dependency chain described above.
- Without L42: 1013 tokens; removes `}` from the dependency chain described above.
- Without L44: 987 tokens; removes `fn height(nodes: &[Node], root: Option<usize>) -> usize {` from the dependency chain described above.
- Without L45: 999 tokens; removes `root.map_or(0, |v| {` from the dependency chain described above.
- Without L46: 982 tokens; removes `1 + height(nodes, nodes[v].left).max(height(nodes, nodes[v].right))` from the dependency chain described above.
- Without L47: 1011 tokens; removes `})` from the dependency chain described above.
- Without L48: 1013 tokens; removes `}` from the dependency chain described above.
- Without L50: 976 tokens; removes `fn erase(nodes: &mut [Node], root: Option<usize>, key: i32) -> Option<usize> {` from the dependency chain described above.
- Without L51: 1004 tokens; removes `let v = root?;` from the dependency chain described above.
- Without L52: 1000 tokens; removes `if key < nodes[v].key {` from the dependency chain described above.
- Without L53: 1000 tokens; removes `let left = nodes[v].left;` from the dependency chain described above.
- Without L54: 993 tokens; removes `nodes[v].left = erase(nodes, left, key);` from the dependency chain described above.
- Without L55: 996 tokens; removes `} else if key > nodes[v].key {` from the dependency chain described above.
- Without L56: 1000 tokens; removes `let right = nodes[v].right;` from the dependency chain described above.
- Without L57: 993 tokens; removes `nodes[v].right = erase(nodes, right, key);` from the dependency chain described above.
- Without L58: 1008 tokens; removes `} else {` from the dependency chain described above.
- Without L59: 997 tokens; removes `if nodes[v].left.is_none() {` from the dependency chain described above.
- Without L60: 1003 tokens; removes `return nodes[v].right;` from the dependency chain described above.
- Without L61: 1011 tokens; removes `}` from the dependency chain described above.
- Without L62: 997 tokens; removes `if nodes[v].right.is_none() {` from the dependency chain described above.
- Without L63: 1003 tokens; removes `return nodes[v].left;` from the dependency chain described above.
- Without L64: 1011 tokens; removes `}` from the dependency chain described above.
- Without L65: 994 tokens; removes `let mut successor = nodes[v].right.unwrap();` from the dependency chain described above.
- Without L66: 994 tokens; removes `while let Some(left) = nodes[successor].left {` from the dependency chain described above.
- Without L67: 1005 tokens; removes `successor = left;` from the dependency chain described above.
- Without L68: 1011 tokens; removes `}` from the dependency chain described above.
- Without L69: 998 tokens; removes `nodes[v].key = nodes[successor].key;` from the dependency chain described above.
- Without L70: 1000 tokens; removes `let right = nodes[v].right;` from the dependency chain described above.
- Without L71: 998 tokens; removes `let successor_key = nodes[successor].key;` from the dependency chain described above.
- Without L72: 991 tokens; removes `nodes[v].right = erase(nodes, right, successor_key);` from the dependency chain described above.
- Without L73: 1012 tokens; removes `}` from the dependency chain described above.
- Without L74: 1009 tokens; removes `Some(v)` from the dependency chain described above.
- Without L79: 1003 tokens; removes `let mut root = None;` from the dependency chain described above.
- Without L80: 958 tokens; removes `for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] {` from the dependency chain described above.
- Without L81: 991 tokens; removes `root = Some(insert(&mut nodes, root, key));` from the dependency chain described above.
- Without L82: 1012 tokens; removes `}` from the dependency chain described above.
- Without L100: 995 tokens; removes `root = erase(&mut nodes, root, 6);` from the dependency chain described above.
- Without L101: 994 tokens; removes `root = erase(&mut nodes, root, 27);` from the dependency chain described above.
- Without L102: 1000 tokens; removes `print!("preorder after deletions:");` from the dependency chain described above.
- Without L103: 1001 tokens; removes `traverse(&nodes, root, 1);` from the dependency chain described above.
- Without L104: 986 tokens; removes `println!("\nheight after deletions: {}", height(&nodes, root));` from the dependency chain described above.
