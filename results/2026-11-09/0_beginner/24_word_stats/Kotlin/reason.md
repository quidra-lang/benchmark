# Task B selection: 24_word_stats / Kotlin

The average divides the exact integer character total by the integer word count. C# / Java cast characters to double before division; Kotlin calls toDouble on it. Thus the present expression already prevents integer truncation while leaving both counts integer-valued; applying a cast only after integer division would be too late.

The character-total construction and actual quotient expression establish both operands and conversion order. Longest/shortest selection, input wording and unrelated reporting do not affect the quotient contract.

Selected complete source lines in `main.kt`: 5, 9. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
