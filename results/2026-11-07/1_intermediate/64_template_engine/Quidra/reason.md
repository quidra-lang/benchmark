# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the section operation from resolved/filtered list to traversal and how to reverse element order while retaining original element indices.
2. Trace context and loop metadata pushes,nested rendering and stack restoration,including value-argument implementations.
3. Preserve original @index/@number/@first/@last meanings,empty-list no-op and rendering of every falsy list element.

## Selected source locations

- `main.qui`: 612, 613, 614, 647, 656, 657, 658, 659, 660, 661, 662, 663

## Evidence and language semantics

The evaluated list is stored as children ids. The indexed collection loop passes extended context and Loop(i,#children) arrays into recursive rendering. Value arguments preserve the caller stacks and restoration is implicit. Traverse original child indices descending,retaining i in both lookup and Loop metadata. Keep empty-list no-op and unconditional rendering for each list item; do not renumber reversed values. Metadata remains @index=i,@number=i+1,@first=(i==0),@last=(i==n-1),so the first emitted reverse-order item can be @last rather than @first.

## Minimization and alternatives

The excerpt starts at resolution/evaluation and retains only the list dispatch,traversal,stack extension/restoration,recursive render and loop-variable formulas. Scalar sections,template lexing,partial lookup,variable escaping and filter internals are unchanged and unnecessary. Including the element truth helper would not help: the list branch never applies it to elements. A loop-only alternative would omit original-position metadata and restoration evidence.

The excerpt contains 374 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
