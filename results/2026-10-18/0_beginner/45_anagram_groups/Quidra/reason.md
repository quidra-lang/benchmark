# Task B selection: 45_anagram_groups / Quidra

## Answer and source dependencies

Insert a `len(group) >= 2` condition inside the group loop and place the existing print statement under it. Keep signature construction and group formation unchanged: every original word still participates. Filtering the insertion-ordered groups during output preserves both first-appearance group order and the order of words inside each retained group. Omit singleton groups without printing a placeholder.

## Selected evidence

Source: `main.qui`. Complete main.qui source lines: 8.
Every selected line is a complete verbatim source line in source order.

The print statement is the operation that must become conditional on the length of its group. Signature construction, group formation and group iteration remain unchanged and need no edits to meet this modification, so they are not selected.

## Semantics and minimization

The excerpt retains the operations needed to support this Task B answer. Imports, unrelated input values, headings and unchanged setup are omitted where they do not establish an answer dependency. Standard library operations use their documented semantics; their implementations do not need to be included. Evidence fragments need not compile independently. This is a dependency-based selection, not a claim of globally minimal token count.

The declaration-syntax migration keeps the same source locations and answer dependencies. The current tokenizer counts are 123 for Task A and 15 for Task B.
