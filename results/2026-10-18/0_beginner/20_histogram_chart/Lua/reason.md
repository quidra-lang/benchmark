# Task B source selection

## Common answer requirements

Locate asterisk repetition count; use ceiling(c/2) while continuing to print original count and existing days/labels/separators/seven lines.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Change only the number of repetitions used to form each bar to ceiling(c/2), equivalently nonnegative integer quotient c/2 plus c modulo2. Do not replace the original stored count: the numeric count after the bar must remain c. The repetition operand or loop bound is the edit site; the day loop and formatting continue unchanged.



## Source evidence and dependencies

The selected locations in `main.lua` are L2. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L2: `for i, day in ipairs(days) do io.write(string.format("%s | %s %d\n", day, string.rep("*", amounts[i]), amounts[i])) end`. This line is the bar repetition operand or its asterisk body; change that length to the rounded-up half-count while retaining the separately printed original count.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **68 tokens** for the selected original complete lines. A contiguous-context alternative spanning L2–L2 costs **68 tokens**; the entire source costs **140 tokens**. The selected set plus the additional context line L1 costs **140 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
