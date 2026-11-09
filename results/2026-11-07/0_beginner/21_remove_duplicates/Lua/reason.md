The three 12 entries occur at zero-based indices 0,2,13 (Lua positions 1,3,14): the first is retained and the other two are skipped. The first-appearance sequence is "12 5 8 3 20 15 7 9", followed by "removed: 7".

seen starts empty; only unseen values set seen[n] and append to remaining. ipairs preserves input order, table.concat supplies separators and the length difference supplies 7.

The literal sequence, membership test, insertion order and removal count establish all three 12 occurrences. Final distinct output alone would lose the evidence for which copies were skipped.
