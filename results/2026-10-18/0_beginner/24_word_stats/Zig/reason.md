# Task B source selection

## Common answer requirements

Locate both extreme-word selections and reverse only their equal-length tie behavior to last occurrence; preserve sentence, count, average and four-line format.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

In left-to-right scans, allow equal lengths to replace the current best: longest uses greater-than-or-equal and shortest less-than-or-equal. In reductions retaining the previous operand on equality, choose the later operand on equality instead. Library selectors that return the first extreme can inspect a reversed view for those two selections, or select by (length,occurrence index) with the appropriate index direction. Do not reverse the original word storage or alter count/average processing. Apply the rule independently to both extremes. A numeric length-index search must find the last matching extreme index. The source sites identify the relevant word occurrences without changing any output labels.



## Source evidence and dependencies

The selected locations in `main.zig` are L13, L14, L15, L16. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L13: `if (count == 0 or word.len > longest.len)`. This line supplies one extreme-length selector, tie comparison, returned candidate or length-comparator dependency; both longest and shortest must use last-occurrence ties.
- L14: `longest = word;`. This line supplies one extreme-length selector, tie comparison, returned candidate or length-comparator dependency; both longest and shortest must use last-occurrence ties.
- L15: `if (count == 0 or word.len < shortest.len)`. This line supplies one extreme-length selector, tie comparison, returned candidate or length-comparator dependency; both longest and shortest must use last-occurrence ties.
- L16: `shortest = word;`. This line supplies one extreme-length selector, tie comparison, returned candidate or length-comparator dependency; both longest and shortest must use last-occurrence ties.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **68 tokens** for the selected original complete lines. A contiguous-context alternative spanning L13–L16 costs **68 tokens**; the entire source costs **439 tokens**. The selected set plus the additional context line L1 costs **83 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
