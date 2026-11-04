# Task B selection — 83_topological_sort / PHP

Select the last eligible course from the ascending list, keeping the null fallback. Keep the original ascending sort because array_diff preserves the input order for the cycle list. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 11, 15, 25.

With the benchmark tokenizer, this selection measures 84 tokens; the previous selection measured 62. The full source is 728 tokens.
