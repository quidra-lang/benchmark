# Task B source selection

## Common answer requirements

Locate the column enumeration shared by every row and board size; reverse it to n-1 through 0 while retaining exhaustive search and conflict checks. Identify first-solution capture and size-eight output dependency.

## Concrete modification analysis

Only the per-row column enumeration changes: use n−1 down to0 (reversed index/range iteration or descending loop). Existing conflict checks, exhaustive recursion, first-solution capture and output automatically use that new order and require no edits.

For C-like loops, begin at the last column and decrement with an appropriate nonnegative termination rule; for range/collection loops, reverse the existing per-row range. Lua needs a negative step; J reverses i.n; Ruby uses descending iteration rather than n.times. Do not change board-size iteration or output column order. In unsigned-index languages prefer a reversed range to subtracting below zero.

## Selected source dependencies

- L11: `      n.times do |column|` — is the per-row column enumeration and its current increasing bounds; this is the only affected operation.

## Semantics and measured alternatives

Final excerpt: **12 tokens** by metric/tokenizer.py tokenize. The prior broader excerpt was **139 tokens**. That sufficient alternative redundantly included unchanged capture, recursion/caller and output code. The final selection retains the actual affected statement and necessary decoded-result linkage. Standard iteration, string equality, list/array ordering and collection operations retain their documented meanings. No Task A program was compiled or executed. This is the lowest-token sufficient reviewed candidate, not a proof of a global optimum.
