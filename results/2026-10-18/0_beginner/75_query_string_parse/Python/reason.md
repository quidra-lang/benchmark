# Task B source selection

## Common answer requirements

Identify where decoded keys and decoded values are accumulated; deduplicate values per decoded key after decoding, including empty values, preserving first occurrence. Preserve all keys, lexicographic key order, and quoted comma-separated values.

## Concrete modification analysis

Deduplicate at the existing decoded-result append or decoded per-key value traversal, preserving the first decoded occurrence and one empty value. Decoder bodies, key sorting and quoted output remain unchanged, so they add no required edit evidence.

The selected calls/assignments link decoded keys and values to the accumulation site. Compare decoded string equality within each key before appending, or apply stable distinct filtering to that decoded value sequence. Do not compare encoded spellings, replace ordered values with an unordered set, or drop blank values. In the flat-entry implementations, advance the accepted-entry count only for a new decoded key/value pair; existing sort/format processing consumes the accepted entries. The Task B valid-program assumption applies to unchanged decoding.

## Selected source dependencies

- L1: `from urllib.parse import parse_qs` — identifies decoded key/value materialization or its ordered append/traversal, which is the deduplication point.
- L10: `    values = parse_qs(query, keep_blank_values=True)` — identifies decoded key/value materialization or its ordered append/traversal, which is the deduplication point.

## Semantics and measured alternatives

Final excerpt: **33 tokens** by metric/tokenizer.py tokenize. The prior broader excerpt was **97 tokens**. That sufficient alternative redundantly included unchanged decoder, sorting and output code. The final selection retains the actual affected statement and necessary decoded-result linkage. Standard iteration, string equality, list/array ordering and collection operations retain their documented meanings. No Task A program was compiled or executed. This is the lowest-token sufficient reviewed candidate, not a proof of a global optimum.
