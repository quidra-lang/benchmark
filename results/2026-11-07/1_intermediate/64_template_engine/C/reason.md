# Task B selection — C

## Answer requirements shared across languages

1. Identify the section operation from resolved/filtered list to traversal and how to reverse element order while retaining original element indices.
2. Trace context and loop metadata pushes,nested rendering and stack restoration,including value-argument implementations.
3. Preserve original @index/@number/@first/@last meanings,empty-list no-op and rendering of every falsy list element.

## Selected source locations

- `main.c`: 721, 722, 723, 724, 789, 791, 797, 798, 799, 800, 801, 802, 803, 804, 805

## Evidence and language semantics

The resolved/filtered v enters the LIST branch. The loop traverses j upward,pushes v->items[j] plus (j,count) into copied stack buffers and recursively renders with increased counts. Parent stack pointers/counts remain unchanged. Replace only the list iteration with descending original indices. Keep the item lookup and Loop pair using that original j; empty lists execute no iteration. The metadata formulas continue to derive index,number,first,last from original positions. Metadata remains @index=i,@number=i+1,@first=(i==0),@last=(i==n-1),so the first emitted reverse-order item can be @last rather than @first.

## Minimization and alternatives

The excerpt starts at resolution/evaluation and retains only the list dispatch,traversal,stack extension/restoration,recursive render and loop-variable formulas. Scalar sections,template lexing,partial lookup,variable escaping and filter internals are unchanged and unnecessary. Including the element truth helper would not help: the list branch never applies it to elements. A loop-only alternative would omit original-position metadata and restoration evidence.

The excerpt contains 495 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
