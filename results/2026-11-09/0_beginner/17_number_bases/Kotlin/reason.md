# Task B selection: 17_number_bases / Kotlin

Lowercase hexadecimal belongs at the existing hex conversion/case stage: use lowercase x formatting in C#, remove the uppercasing of the already-lowercase Java/Kotlin radix result. 43981 becomes hex=abcd. Existing conversion semantics already emit 0 for zero, no prefix and no unnecessary leading zeros, while the other three fields remain unchanged.

The input binding and common output expression expose the affected stage and unaffected conversions. No radix-conversion implementation is needed for standard APIs.

Selected complete source lines in `main.kt`: 2, 3. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
