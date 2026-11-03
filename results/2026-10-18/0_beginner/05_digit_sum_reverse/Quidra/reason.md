# Task B selection: 05_digit_sum_reverse / Quidra

## Common answer requirements

1. For the question-supplied integer 98000, explain digit count, digit sum and reversed integer.
2. Identify how text length includes zero characters, parsed zeros add zero, and integer parsing removes reversed leading zeros.
3. Derive the complete formatted output line.

## Implementation decision

Replace the unsupported old generation header with the current collection-binding generation form over a typed natural index range. This preserves decimal-string processing, the explicitly typed integer digit array and the reversal/parsing algorithm. It adds the syntax required by the current compiler rather than removing type information.

## Evidence and answer

The selected string conversion establishes the decimal text; the generation, sum and reverse parse distinguish the treatments of zeros, and the print line associates the quantities with their labels. The question supplies 98000, so the other input values and the outer loop do not contribute to the focused trace. import math binds the sum extension.

## Selection and minimization

Selected complete main.qui lines: 1, 5, 6, 7, 8. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 171 → 176; Task B 108 → 113. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
