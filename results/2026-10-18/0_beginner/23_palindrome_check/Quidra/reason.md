# Task B selection: 23_palindrome_check / Quidra

## Common answer requirements

1. Identify the filtered lowercase sequence for Step on no pets. and its palindrome result.
2. Explain why the original capital, spaces and period remain in printed phrase.

## Implementation decision

Give each complete phrase its own input-record line, matching the existing Python fixture's ordinary list layout. This improves readability of independent phrases and avoids coupling the focused phrase with an unrelated neighboring phrase in a complete-line evidence slice. No input, algorithm or output expression changes.

## Evidence and answer

The declaration and focused phrase literal establish the actual input spelling and final period; the value-loop binder connects it to phrase. text.ascii_words with ignore_case=true removes non-ASCII-letter separators and normalizes letters; joining produces steponnopets. That equals its reversed string, selecting yes. These operations return new string values, so phrase retains its original spelling for print. The other five phrase records provide no required focused-trace information. import text supplies the documented helper contract.

## Selection and minimization

Selected complete main.qui lines: 1, 3, 8, 11, 12, 13, 14. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 185 → 178; Task B 130 → 107. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
