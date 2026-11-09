# Task B selection — Lua

## Answer requirements shared across languages

1. Identify the section operation from resolved/filtered list to traversal and how to reverse element order while retaining original element indices.
2. Trace context and loop metadata pushes,nested rendering and stack restoration,including value-argument implementations.
3. Preserve original @index/@number/@first/@last meanings,empty-list no-op and rendering of every falsy list element.

## Selected source locations

- `main.lua`: 649, 653, 654, 655, 656, 657, 658, 659, 660, 705, 710, 711, 712, 713, 714, 715

## Evidence and language semantics

The list branch traverses ipairs(v.items),whose i is one-based. It pushes the item and zero-based original index i-1 with count,visits children and removes both tails. Use descending original one-based indices and retain i-1 in metadata. Keep visit and restoration unchanged. Empty lists skip traversal; no per-element truth test excludes falsy items. Metadata remains @index=i,@number=i+1,@first=(i==0),@last=(i==n-1),so the first emitted reverse-order item can be @last rather than @first.

## Minimization and alternatives

The excerpt starts at resolution/evaluation and retains only the list dispatch,traversal,stack extension/restoration,recursive render and loop-variable formulas. Scalar sections,template lexing,partial lookup,variable escaping and filter internals are unchanged and unnecessary. Including the element truth helper would not help: the list branch never applies it to elements. A loop-only alternative would omit original-position metadata and restoration evidence.

The excerpt contains 280 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
