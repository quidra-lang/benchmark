# Task B selection: 30_set_operations / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Modify only the difference result so that it contains values that occur in B but not in A, instead of values that occur in A but not in B. Keep the label difference: and its position as the third output line. Continue removing duplicates and listing that result in increasing order.

The union, intersection and symmetric-difference results retain their original meanings. All other Task A requirements remain unchanged.

## Source evidence and minimization

The Collections import and both construction calls establish native distinct values, so the documented difference contract applies. Reverse only left and right in the selected difference call. Its label and sorted values remain unchanged. Raw input data, other set operations and the unaffected display helper are unnecessary for this local modification. Python includes its native set construction under the same criterion.

Locations in main source: L1, L9, L10, L13.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 252; Task B 57. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
