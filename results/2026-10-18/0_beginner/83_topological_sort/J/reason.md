# Task B selection — 83_topological_sort / J

The candidate indices come from the zero-indegree/untaken mask over ascending names. Select the last available index rather than the head; the cycle mask also reads names in ascending order, so do not reverse that array. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 3, 13, 15, 28.

With the benchmark tokenizer, this selection measures 72 tokens; the previous selection measured 44. The full source is 541 tokens.
