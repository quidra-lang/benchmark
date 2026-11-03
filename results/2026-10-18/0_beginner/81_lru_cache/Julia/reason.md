# Task B source selection

## Common answer requirements

Locate all capacity-dependent storage, miss thresholds and fixed eviction indices/slices; explain capacity four while preserving recency and existing output.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Change the full-cache threshold from three to four. Dynamic collections require no storage-size change; fixed arrays must hold four keys. If eviction uses a literal last index or prefix length of two, change it to three, so the fourth (least recent) key is removed and three survivors remain before insertion. Existing end-removal operations already follow the collection length. These are the only capacity-dependent edits; existing refresh, insertion, counters and printers consume the resulting cache state automatically.



## Source evidence and dependencies

The selected locations in `main.jl` are L12. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L12: `result = length(cache) == 3 ? string("miss, evict ", pop!(cache)) : "miss"`. This is a capacity-dependent bound or fixed last-element/storage dependency; changing only the threshold would be insufficient when an array size or literal eviction index also appears.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **42 tokens** for the selected original complete lines. A contiguous-context alternative spanning L12–L12 costs **42 tokens**; the entire source costs **311 tokens**. The selected set plus the additional context line L1 costs **48 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
