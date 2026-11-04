# Task B selection: 75_query_string_parse / Quidra

## Common answer requirements

Locate the decoded values, deduplicate each key in first appearance order, and retain the existing sorting and value format.

## Supported analysis

Compare decoded strings for equality within a decoded key. Use a stable filter or guard the per-key append, retaining the first empty string like any other value. For a flat entry array, compare the decoded key/value pair before storing or sorting it; for grouped pairs, compare only the decoded value component within the key group. Retain every key by keeping its first value. The downstream sort and quoted comma-separated formatter do not need edits.

The excerpt is copied verbatim from `main.qui`, in source order. Retained source lines: 11.

## Minimization and alternatives

Changing the decoded producer/group is sufficient. Retain the parser binding or concrete key/value decode and insertion operands where the filter belongs; neither percent-decoding internals nor the unchanged display are needed to implement the filter. The prior selection used 29 tokens; this selection uses 25 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

Measurement: Task A 257; Task B 25. Tokenizer: metric/tokenizer.py, unchanged.
