# Task B selection: 37_bubble_sort_passes / Quidra

## Common answer requirements

[Code comprehension]

Using the source code, trace the comparisons involving 88 during the first bubble-sort pass. Explain how its position changes as the pass proceeds and why it ends at the final array position. Identify how the pass bounds keep that settled position outside the comparisons in the second pass, and distinguish these comparisons from the total swap count.

## Source evidence and minimization

The initial array, first-pass and inner-loop bounds, strict adjacent comparison, swap and swap-counter increment establish every movement of 88. The second-pass bound excludes the settled last position. The count records successful swaps across passes, rather than all comparisons. Changed output formatting does not participate in these facts.

Locations in main source: L3, L4, L5, L7, L8, L9, L10.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 218; Task B 144. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
