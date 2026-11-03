# Task B selection: 38_insertion_sort_steps / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Modify the insertion sort to produce decreasing order while remaining stable. At each step, shift only sorted-prefix values strictly smaller than the value being inserted; equal values must retain their original relative order. Continue processing positions 1 through 7 and report the array and number of right shifts after each step, followed by the total shifts.

Keep the original input and output labels and spacing. All other Task A requirements remain unchanged.

## Source evidence and minimization

The strict greater-than condition and right-shift assignment identify the sole ordering change: use strict less-than for descending order. Equality still performs no shift, preserving stable order. Bounds, counters and display remain unaffected.

Locations in main source: L9, L10.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 225; Task B 38. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
