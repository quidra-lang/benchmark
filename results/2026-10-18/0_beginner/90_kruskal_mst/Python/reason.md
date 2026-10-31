# Task B source selection

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Source evidence and dependencies

The selected locations in `main.py` are L1, L2, L3, L4, L5, L6, L7, L8, L9, L12, L14, L15, L17, L20, L21, L22, L23, L24, L27, L28, L29, L30, L31, L32, L33, L34, L38, L39. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `vertices = "ABCDEFGH"`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L2: `edges = [`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L3: `("A", "B", 7),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L4: `("C", "A", 4),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L5: `("B", "C", 9),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L6: `("B", "D", 14),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L7: `("D", "C", 6),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L8: `("C", "E", 3),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L9: `("E", "D", 5),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L12: `("G", "F", 8),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L14: `("G", "H", 2),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L15: `("H", "E", 10),`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L17: `parent = {vertex: vertex for vertex in vertices}`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L20: `def find(vertex):`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L21: `while parent[vertex] != vertex:`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L22: `parent[vertex] = parent[parent[vertex]]`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L23: `vertex = parent[vertex]`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L24: `return vertex`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L27: `accepted = skipped = total = 0`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L28: `for a, b, weight in sorted(edges, key=lambda edge: edge[2]):`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L29: `root_a, root_b = find(a), find(b)`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L30: `if root_a == root_b:`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L31: `skipped += 1`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L32: `continue`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L33: `parent[root_b] = root_a`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L34: `accepted += 1`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L38: `if accepted == len(vertices) - 1:`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.
- L39: `break`. This line supplies edge identities/weights, weight order, component-root semantics, root merging, equal-root skipping or the seven-edge stop. These distinguish examined cycle edges from edges never examined.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **384 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L39 costs **485 tokens**; the entire source costs **513 tokens**. The selected set plus the additional context line L10 costs **401 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
