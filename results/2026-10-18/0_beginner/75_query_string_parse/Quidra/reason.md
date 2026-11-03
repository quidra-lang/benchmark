# Task B selection: 75_query_string_parse / Quidra

## Answer requirements

Locate decoding and explain stable value deduplication after decoding while preserving keys and display.

## Source evidence and supported analysis

The Text query parser returns an insertion-ordered map from decoded keys to decoded value arrays. Stable-deduplicate each array immediately after parsing, or immediately before its quoting comprehension, so equivalent encodings and repeated empty strings collapse to their first decoded occurrence. Sorted tuple entries preserve lexicographic key order and each array's value order. The parse binding is the necessary change boundary; unchanged sorting and quoting do not require modification.

Selected complete `main.qui` lines: 2, 11. Every excerpt line is copied verbatim in source order. Ordinary language and documented package semantics apply; the excerpt need not compile independently. User-defined behavior is supported by its selected operations, not by a helper name.

## Selection and measurement

The retained declarations, input values, control flow, calculations and change sites support the requested Task B answer. Unchanged unrelated processing and output are omitted. The complete source and the enclosing contiguous span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **289** tokens; Task B **29** tokens. These measurements describe lexical source evidence; execution verification is recorded separately.

The typed successful map binding unwraps query parsing before generic collection operations. Library failures retain normal propagation.
