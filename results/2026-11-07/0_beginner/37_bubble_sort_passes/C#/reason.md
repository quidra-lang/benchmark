# Task B selection: 37_bubble_sort_passes / C#

The first pass carries 88 rightward to the last slot through adjacent comparisons. Each pass resets changed, compares through 7-p, prints the resulting array, then stops if no swap occurred. The sorted result is 5 13 27 36 41 64 72 88; pass 6 is printed despite no swap, and final swaps: 14 follows.

The array, bounds, swap/flag/counter updates and print-before-break order are all needed for the exact final pass and total. Imports and main/culture scaffolding add no sorting evidence.

Selected complete source lines in `Program.cs`: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
