# Task B source selection

## Common answer requirements

Trace all three 12 occurrences, retain first/exclude later two, account for exclusions in removed count, and establish first-appearance rather than numerical order.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The 12 occurrences are at one-based positions1,3,14. The first encounters no existing12 and is retained. The second and third encounter12 already present and contribute no additional element. Their two exclusions contribute two to the total removed count. The stable distinct result is 12,5,8,3,20,15,7,9: eight retained out of fifteen, so removed is seven. Left-to-right filtering/appending or insertion-ordered distinct-library semantics retains first appearances; no numeric sort is used.



## Source evidence and dependencies

The selected locations in `main.lua` are L1, L2, L3, L4, L5, L6, L9. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `local numbers = {12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9}`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L2: `local seen, remaining = {}, {}`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L3: `for _, n in ipairs(numbers) do`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L4: `if not seen[n] then`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L5: `seen[n] = true`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L6: `remaining[#remaining + 1] = n`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.
- L9: `io.write(table.concat(remaining, " "), "\n", string.format("removed: %d\n", #numbers - #remaining))`. This line supplies input occurrence order, stable uniqueness membership/insertion semantics, or original-minus-retained counting; together they trace the first12 and its two later exclusions.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **182 tokens** for the final selected lines. The prior candidate measured 177 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Finish the membership/input traversal before computing the final removed count, so both later12 occurrences are excluded before the15-minus-retained calculation.

Final original source lines: L1, L2, L3, L4, L5, L6, L7, L8, L9.
- L7: `    end` — Finish the membership/input traversal before computing the final removed count, so both later12 occurrences are excluded before the15-minus-retained calculation.
- L8: `end` — Finish the membership/input traversal before computing the final removed count, so both later12 occurrences are excluded before the15-minus-retained calculation.

Final selection: 182 metric tokens; contiguous span L1–L9: 182 tokens; complete source: 182 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
