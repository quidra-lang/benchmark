# Task B source selection

## Common answer requirements

Locate completed-tree traversal bit labels; reverse left/right labels while keeping tree priorities/child selection, ASCII print order and length-based bit totals.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Swap the literal bit appended or written before the left recursive move from 0 to 1, and the right move from 1 to 0. Keep the completed tree and its left/right children unchanged. Every code becomes its bitwise complement with exactly the same length, so frequency-times-length encoded-bit totals and the fixed eight-bit comparison retain their values. The existing symbol-order printer consumes the newly assigned codes without an ordering/format change. There is no reason to alter frequency collection or queue priorities.



## Source evidence and dependencies

The selected locations in `main.qui` are L14, L15. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L14: `assign_codes(left[node], prefix + "0", left, right, symbols, &codes)`. This line supplies the current bit literal or its association with the left/right recursive child; both associations are needed to reverse labels without swapping children.
- L15: `assign_codes(right[node], prefix + "1", left, right, symbols, &codes)`. This line supplies the current bit literal or its association with the left/right recursive child; both associations are needed to reverse labels without swapping children.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **66 tokens** for the selected original complete lines. A contiguous-context alternative spanning L14–L15 costs **66 tokens**; the entire source costs **1007 tokens**. The selected set plus the additional context line L1 costs **88 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
