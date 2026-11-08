# Task B selection — Java

## Answer requirements shared across languages

1. Identify the section operation from resolved/filtered list to traversal and how to reverse element order while retaining original element indices.
2. Trace context and loop metadata pushes,nested rendering and stack restoration,including value-argument implementations.
3. Preserve original @index/@number/@first/@last meanings,empty-list no-op and rendering of every falsy list element.

## Selected source locations

- `Main.java`: 478, 479, 480, 481, 482, 483, 522, 524, 525, 531, 532, 533, 534, 535, 536, 537, 538

## Evidence and language semantics

The resolved/filtered List is traversed with ascending i; contexts receives items.get(i),loops receives (i,size),children render,and both lists lose the appended tail. Reverse traversal over original indices,retaining original i in the pair and preserving push/render/pop. Empty lists skip iteration; there is no truth check on list items. Metadata remains @index=i,@number=i+1,@first=(i==0),@last=(i==n-1),so the first emitted reverse-order item can be @last rather than @first.

## Minimization and alternatives

The excerpt starts at resolution/evaluation and retains only the list dispatch,traversal,stack extension/restoration,recursive render and loop-variable formulas. Scalar sections,template lexing,partial lookup,variable escaping and filter internals are unchanged and unnecessary. Including the element truth helper would not help: the list branch never applies it to elements. A loop-only alternative would omit original-position metadata and restoration evidence.

The excerpt contains 371 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
