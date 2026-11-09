# Task B selection — Kotlin

## Answer requirements shared across languages

1. Identify the section operation from resolved/filtered list to traversal and how to reverse element order while retaining original element indices.
2. Trace context and loop metadata pushes,nested rendering and stack restoration,including value-argument implementations.
3. Preserve original @index/@number/@first/@last meanings,empty-list no-op and rendering of every falsy list element.

## Selected source locations

- `main.kt`: 543, 544, 545, 546, 547, 548, 597, 598, 599, 600, 601, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632

## Evidence and language semantics

Resolved/filtered ListValue uses withIndex ascending. Recursive render receives contexts+item and loops+(original i,size); immutable List extension leaves parent stacks intact. Reverse the sequence of indexed entries,or traverse original indices descending; preserve i rather than enumerating reversed values. Empty lists stay empty and every item,including falsy values,is rendered. Metadata remains @index=i,@number=i+1,@first=(i==0),@last=(i==n-1),so the first emitted reverse-order item can be @last rather than @first.

## Minimization and alternatives

The excerpt starts at resolution/evaluation and retains only the list dispatch,traversal,stack extension/restoration,recursive render and loop-variable formulas. Scalar sections,template lexing,partial lookup,variable escaping and filter internals are unchanged and unnecessary. Including the element truth helper would not help: the list branch never applies it to elements. A loop-only alternative would omit original-position metadata and restoration evidence.

The excerpt contains 455 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
