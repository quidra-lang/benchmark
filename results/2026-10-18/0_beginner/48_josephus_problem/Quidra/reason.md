# Task B selection: 48_josephus_problem / Quidra

## Common answer requirements

Trace the first three removals for n=7,k=3, resumed counting and wrap-around.

## Source evidence and minimization

Task B provides n and k; the typed loop binder establishes their roles, so the full case collection is unnecessary. The inclusive 1:n range gives people 1 through 7. Starting from index zero, (index+k-1) modulo the current length selects index 2/person 3, then index 4/person 6, then wraps to index 1/person 2. The indexed read followed by Collections remove deletes that current person. Because the range has unique values, removing the first equal value removes exactly that indexed person; the unchanged index then points to its successor. The import establishes the documented mutation operation. Python retains its case values because they share the required loop-header line; no source is reformatted merely to split them.

Selected original source lines: L1, L4, L5, L6, L9, L10, L11, L13.
Every selected line is complete, verbatim and in source order. Alternative complete
source and contiguous-context selections retain unrelated information; the removed
input records or independent operations add no required fact. This is a reviewed
sufficient minimized candidate, not a proof of a global mathematical minimum.
Language and documented library semantics are available as prior knowledge.

Task B: 104 tokens under the unchanged metric/tokenizer.py. Task A is unchanged
by this evidence correction.
