# Task B source selection

## Common answer requirements

Trace all three 12 occurrences, retain first/exclude later two, account for exclusions in removed count, and establish first-appearance rather than numerical order.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The 12 occurrences are at one-based positions1,3,14. The first encounters no existing12 and is retained. The second and third encounter12 already present and contribute no additional element. Their two exclusions contribute two to the total removed count. The stable distinct result is 12,5,8,3,20,15,7,9: eight retained out of fifteen, so removed is seven. Left-to-right filtering/appending or insertion-ordered distinct-library semantics retains first appearances; no numeric sort is used.



## Source evidence and dependencies

The selected locations in `main.jl` are L1, L2, L4. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `numbers = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9]`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L2: `remaining = unique(numbers)`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L4: `println("removed: ", length(numbers) - length(remaining))`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **87 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L4 costs **100 tokens**; the entire source costs **100 tokens**. The selected set plus the additional context line L3 costs **100 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
