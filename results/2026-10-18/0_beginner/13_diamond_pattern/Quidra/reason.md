# Task B selection: 13_diamond_pattern / Quidra

## Common answer requirements

1. Derive the leading-space and asterisk counts on rows five and six of the size-five diamond.
2. Explain the switch from expansion to contraction without duplicating the widest line.

## Implementation decision

Use explicit nat types for the diamond size, row index and positive half-row size. These values denote sizes and remain nonnegative under the existing loop and conditional. This removes both conversions at string.repeat while preserving all arithmetic and row order.

## Evidence and answer

All four substantive lines are necessary: n fixes the size; the loop defines the row traversal; the conditional yields i = 5 then 4 for the two rows; and repeat counts yield 0 spaces/9 stars then 1 space/7 stars. The same conditional uses row <= n, so the widest row appears once. string.repeat takes a natural count and returns repeated characters.

## Selection and minimization

Selected complete main.qui lines: 1, 2, 3, 4. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 107 → 97; Task B 107 → 97. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
