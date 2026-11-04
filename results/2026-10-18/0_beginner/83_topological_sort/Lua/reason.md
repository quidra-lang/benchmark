# Task B selection — 83_topological_sort / Lua

Scan the sorted names in reverse for the current first eligible match, retaining the existing no-match behavior. The remaining list scans the same sorted names forward; reversing the shared sort would affect that output. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 12, 15, 16, 17, 18, 19, 28, 29.

With the benchmark tokenizer, this selection measures 119 tokens; the previous selection measured 82. The full source is 806 tokens.
