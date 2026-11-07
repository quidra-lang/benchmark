# Task B selection: 45_anagram_groups / C++

Locate the group membership and output boundary; explain how to omit singletons while keeping the key rule, word order and first-appearance order.

Keep building groups from all twelve words using the existing signature. For code with materialized groups, test the finished group size immediately before its output and suppress the whole line when the size is one. For code that streams words directly, count matches with the same signature test before any write, or accumulate the matched words first. Preserve the existing first-unused/index or insertion-order traversal and the original append order. Do not print a blank line for a singleton.

The loop over completed groups supplies the insertion site for the check without tracing the original grouping procedure. For immediate writes, the existing equality test and newline are both needed: suppressing the printed words alone could still emit a placeholder.

The key is the sorted copy of the word. The first unused index and increasing inner index already provide group and word order; count matches before either the words or newline are written.

Source: `main.cpp`, original lines 10, 13–24. The previous excerpt measures 134 tokens; this evidence set measures 219 tokens.

## Current token measurement

Task A: **399 tokens**. Task B: **219 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
