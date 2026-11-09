# Task B selection — Zig

## Answer requirements shared across languages

1. Explain assignment/addition composition, aggregate effects, and why a later assignment discards an older pending addition.
2. Explain the ordered assignment-then-addition push to both children, parent-tag clearing, and one push count per nonempty propagation.
3. Explain full-cover update/query behavior and how partial queries redistribute pending tags while preserving logical values.
4. Establish the complete query control flow: recursive result combination performs no pull-up or logical-array update.

## Selected source locations

- `main.zig`: 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 218, 219, 220, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317

## Evidence and language semantics

The apply/assign/add code shows that assigning c replaces sum/min/max and resets the deferred addition, whereas adding d translates the aggregate and accumulates d. Thus a pending assignment a followed by addition d denotes x -> a+d; retaining an older d after a new assignment would incorrectly reapply an overwritten update. Push first transfers assignment and then addition to each child, clears the parent tags, and counts one nonempty parent propagation rather than two child operations. The full-cover update applies once and returns; the full-cover query returns the already updated aggregate without pushing. The entire partial-query body pushes before descent and returns the appropriate child or combined answer, with no pull or array assignment. For example, a partial query under pending assignment 5/addition 2 changes tag placement but still represents 7 at every affected element; a later covered query can read the unchanged parent aggregate. The nullable assignment is checked for presence and unwrapped before use. *LazyTree permits the displayed mutations; query returns new LazyAnswer records and propagates push totals explicitly.

## Minimization and alternatives

The candidate containing complete LAZY build/update/dump/command-dispatch code was reduced to tag application/propagation, the full-cover update branch, and the complete query path. Uncovered update recursion and pull-ups are unnecessary for this query question. Custom coverage/leaf/length and aggregate arithmetic are retained where called; standard arithmetic, optional/null semantics and value/reference rules need no library implementation. A tags-only excerpt is shorter but cannot establish that aggregates remain correct, full coverage avoids propagation, counts are per propagation, or that every query path lacks a pull-up. A query-only excerpt cannot explain composition. Constructors, formatting and unrelated structures add no required fact; initial counters are retained only where the query uses a shared accumulator. Independently reading this excerpt supports all four requirements; no omitted source is needed to infer a query-side pull-up or an array-value mutation.

The excerpt contains 1208 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
