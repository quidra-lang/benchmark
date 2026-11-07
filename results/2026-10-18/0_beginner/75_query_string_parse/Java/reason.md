# Task B selection: 75_query_string_parse / Java

## Common answer requirements

Locate the decoded values, deduplicate each key in first appearance order, and retain the existing sorting and value format.

## Supported analysis

Compare decoded strings for equality within a decoded key. Use a stable filter or guard the per-key append, retaining the first empty string like any other value. For a flat entry array, compare the decoded key/value pair before storing or sorting it; for grouped pairs, compare only the decoded value component within the key group. Retain every key by keeping its first value. The downstream sort and quoted comma-separated formatter do not need edits.

The excerpt is copied verbatim from `Main.java`, in source order. Retained source lines: 18, 19, 20.

## Minimization and alternatives

Changing the decoded producer/group is sufficient. Retain the parser binding or concrete key/value decode and insertion operands where the filter belongs; neither percent-decoding internals nor the unchanged display are needed to implement the filter. The prior selection used 156 tokens; this selection uses 129 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

## Current token measurement

Task A: **604 tokens**. Task B: **128 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
