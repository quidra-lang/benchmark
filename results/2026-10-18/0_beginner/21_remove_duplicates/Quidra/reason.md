# Task B selection: 21_remove_duplicates / Quidra

## Common answer requirements

[Code comprehension]

Using the source code, trace what happens to the three occurrences of 12 in the given array. Explain how the code retains the first one, excludes the later ones, and accounts for those exclusions in the removed count. Identify how it preserves first-appearance order rather than placing the remaining values in numerical order.

## Source evidence and minimization

The input places 12 at indices 0, 2 and 13. The documented unique operation retains first occurrences in encounter order, so only the first 12 survives; 15 input values minus 8 remaining values gives 7 removals overall. The other two occurrences of 12 contribute two of those removals. The selected import establishes the first-party API; display formatting is unrelated.

Locations in main source: L2, L4, L5, L6.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 130; Task B 95. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
