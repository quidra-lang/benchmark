# Task B source selection

## Common answer requirements

Trace all three 12 occurrences, retain first/exclude later two, account for exclusions in removed count, and establish first-appearance rather than numerical order.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The 12 occurrences are at one-based positions1,3,14. The first encounters no existing12 and is retained. The second and third encounter12 already present and contribute no additional element. Their two exclusions contribute two to the total removed count. The stable distinct result is 12,5,8,3,20,15,7,9: eight retained out of fifteen, so removed is seven. Left-to-right filtering/appending or insertion-ordered distinct-library semantics retains first appearances; no numeric sort is used.

The set library insertion/values contract supplies distinct values in insertion order; duplicate add does not add another element or reposition the first one.

## Source evidence and dependencies

The selected locations in `main.qui` are L1, L2, L3, L4, L5, L7. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `int[] values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9]`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L2: `set.Set<int> seen = set.Set<int>()`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L3: `for int value = values[]`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L4: `.seen.add(value)`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L5: `int[] unique = seen.values()`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L7: `int removed = int(len(values)) - int(len(unique))`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **136 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L7 costs **164 tokens**; the entire source costs **192 tokens**. The selected set plus the additional context line L6 costs **164 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.


## Library contract checked in independent review

The official [Quidra set contract](https://github.com/quidra-lang/quidra/blob/develop/docs/spec/language.md#set), docs/spec/language.md blob81addca18411c6bf62fe63f5a1e6dc069660620d, specifies that add preserves the first insertion position and values returns insertion order. This establishes first-appearance retention without inspecting implementation internals.
