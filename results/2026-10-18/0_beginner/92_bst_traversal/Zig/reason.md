# Task B selection: 92_bst_traversal / Zig

## Common answer requirements

Trace deleting 6 then 27, successor selection/replacement and right-child reconnection; derive local subtree, post-deletion preorder and height.

## Answer and source dependencies

After leaf 6 is removed, 27 has left child 13 and right child 39. The minimum of 27’s right subtree is 31 (39’s left child), whose existing right child is 34. The deletion copies key 31 into the former 27 node and recursively removes the original successor. At that original node the no-left-child case returns its right child 34; assignment while unwinding makes 39.left = 34. The local subtree is root 31, left 13, right 39, with 39 children 34 and 45. Preorder visits root, left, right, giving 50 31 13 39 34 45 74 62 70 88. Height uses empty=0 and one plus maximum child height, giving four after deletions (the old longest branch through both 27 and 31 has shortened).



## Scope and dependency evidence checked after independent review

Finish null/one-child branches before recursive two-child processing, finish successor descent before copying31, and close the equality branch before returning the updated root. Initial insertion completes before deleting6 then27; preorder/height and any display helper must preserve the derived local shape31(13,39(34,45)). Constructor/empty traversal-list bindings establish actual keys/children and fresh post-deletion output where needed.

Source: `main.zig`. Selected original locations: L3,L5,L6,L7,L8,L9,L12,L15,L17,L18,L19,L20,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L83,L84,L85,L86,L87.

- L3: `const Node = struct { key: i32, left: ?usize = null, right: ?usize = null };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `fn traverse(out: *std.Io.Writer, nodes: *const [12]Node, root: ?usize, mode: usize) std.Io.Writer.Error!void {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    const i = root orelse return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    if (mode == 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        try out.print(" {d}", .{nodes[i].key});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    try traverse(out, nodes, nodes[i].left, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    try traverse(out, nodes, nodes[i].right, mode);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `fn height(nodes: *const [12]Node, root: ?usize) usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    const i = root orelse return 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    return 1 + @max(height(nodes, nodes[i].left), height(nodes, nodes[i].right));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `fn remove(nodes: *[12]Node, root: ?usize, key: i32) ?usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    const i = root orelse return null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    if (key < nodes[i].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        nodes[i].left = remove(nodes, nodes[i].left, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    } else if (key > nodes[i].key) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        nodes[i].right = remove(nodes, nodes[i].right, key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if (nodes[i].left == null)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            return nodes[i].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        if (nodes[i].right == null)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            return nodes[i].left;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        var successor = nodes[i].right.?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        while (nodes[successor].left) |next|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            successor = next;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        nodes[i].key = nodes[successor].key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        nodes[i].right = remove(nodes, nodes[i].right, nodes[successor].key);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `    return i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `    var root: ?usize = null;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    for ([_]i32{ 50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34 }) |key| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        var link = &root;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        while (link.*) |i| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `            link = if (key < nodes[i].key) &nodes[i].left else &nodes[i].right;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L54: `        nodes[len] = .{ .key = key };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        link.* = len;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        len += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L83: `    root = remove(&nodes, root, 6);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L84: `    root = remove(&nodes, root, 27);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L85: `    try out.writeAll("preorder after deletions:");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L86: `    try traverse(out, &nodes, root, 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `    try out.print("\nheight after deletions: {d}\n", .{height(&nodes, root)});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **881 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 865 tokens. The contiguous original span L3–L87 costs 1446 tokens; the complete original source costs 1474 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 841 tokens; removes `const Node = struct { key: i32, left: ?usize = null, right: ?usize = null };` from the dependency chain described above.
- Without L5: 828 tokens; removes `fn traverse(out: *std.Io.Writer, nodes: *const [12]Node, root: ?usize, mode: usize) std.Io.Writer.Error!void {` from the dependency chain described above.
- Without L6: 867 tokens; removes `const i = root orelse return;` from the dependency chain described above.
- Without L7: 870 tokens; removes `if (mode == 1)` from the dependency chain described above.
- Without L8: 854 tokens; removes `try out.print(" {d}", .{nodes[i].key});` from the dependency chain described above.
- Without L9: 859 tokens; removes `try traverse(out, nodes, nodes[i].left, mode);` from the dependency chain described above.
- Without L12: 859 tokens; removes `try traverse(out, nodes, nodes[i].right, mode);` from the dependency chain described above.
- Without L15: 879 tokens; removes `}` from the dependency chain described above.
- Without L17: 853 tokens; removes `fn height(nodes: *const [12]Node, root: ?usize) usize {` from the dependency chain described above.
- Without L18: 865 tokens; removes `const i = root orelse return 0;` from the dependency chain described above.
- Without L19: 844 tokens; removes `return 1 + @max(height(nodes, nodes[i].left), height(nodes, nodes[i].right));` from the dependency chain described above.
- Without L20: 879 tokens; removes `}` from the dependency chain described above.
- Without L22: 848 tokens; removes `fn remove(nodes: *[12]Node, root: ?usize, key: i32) ?usize {` from the dependency chain described above.
- Without L23: 865 tokens; removes `const i = root orelse return null;` from the dependency chain described above.
- Without L24: 864 tokens; removes `if (key < nodes[i].key) {` from the dependency chain described above.
- Without L25: 855 tokens; removes `nodes[i].left = remove(nodes, nodes[i].left, key);` from the dependency chain described above.
- Without L26: 860 tokens; removes `} else if (key > nodes[i].key) {` from the dependency chain described above.
- Without L27: 855 tokens; removes `nodes[i].right = remove(nodes, nodes[i].right, key);` from the dependency chain described above.
- Without L28: 874 tokens; removes `} else {` from the dependency chain described above.
- Without L29: 865 tokens; removes `if (nodes[i].left == null)` from the dependency chain described above.
- Without L30: 869 tokens; removes `return nodes[i].right;` from the dependency chain described above.
- Without L31: 865 tokens; removes `if (nodes[i].right == null)` from the dependency chain described above.
- Without L32: 869 tokens; removes `return nodes[i].left;` from the dependency chain described above.
- Without L33: 865 tokens; removes `var successor = nodes[i].right.?;` from the dependency chain described above.
- Without L34: 865 tokens; removes `while (nodes[successor].left) |next|` from the dependency chain described above.
- Without L35: 871 tokens; removes `successor = next;` from the dependency chain described above.
- Without L36: 864 tokens; removes `nodes[i].key = nodes[successor].key;` from the dependency chain described above.
- Without L37: 851 tokens; removes `nodes[i].right = remove(nodes, nodes[i].right, nodes[successor].key);` from the dependency chain described above.
- Without L38: 878 tokens; removes `}` from the dependency chain described above.
- Without L39: 875 tokens; removes `return i;` from the dependency chain described above.
- Without L40: 879 tokens; removes `}` from the dependency chain described above.
- Without L48: 867 tokens; removes `var root: ?usize = null;` from the dependency chain described above.
- Without L49: 816 tokens; removes `for ([_]i32{ 50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34 }) |key| {` from the dependency chain described above.
- Without L50: 869 tokens; removes `var link = &root;` from the dependency chain described above.
- Without L51: 866 tokens; removes `while (link.*) |i| {` from the dependency chain described above.
- Without L52: 843 tokens; removes `link = if (key < nodes[i].key) &nodes[i].left else &nodes[i].right;` from the dependency chain described above.
- Without L53: 877 tokens; removes `}` from the dependency chain described above.
- Without L54: 859 tokens; removes `nodes[len] = .{ .key = key };` from the dependency chain described above.
- Without L55: 871 tokens; removes `link.* = len;` from the dependency chain described above.
- Without L56: 872 tokens; removes `len += 1;` from the dependency chain described above.
- Without L57: 878 tokens; removes `}` from the dependency chain described above.
- Without L83: 863 tokens; removes `root = remove(&nodes, root, 6);` from the dependency chain described above.
- Without L84: 862 tokens; removes `root = remove(&nodes, root, 27);` from the dependency chain described above.
- Without L85: 862 tokens; removes `try out.writeAll("preorder after deletions:");` from the dependency chain described above.
- Without L86: 862 tokens; removes `try traverse(out, &nodes, root, 1);` from the dependency chain described above.
- Without L87: 843 tokens; removes `try out.print("\nheight after deletions: {d}\n", .{height(&nodes, root)});` from the dependency chain described above.
