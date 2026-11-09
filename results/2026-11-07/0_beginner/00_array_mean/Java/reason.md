# Task B selection: 00_array_mean / Java

The numeric mean remains a double before formatting. F2 / %.2f converts that value to fixed two-place text, rounding only the display and retaining a trailing zero; WriteLine / %n / println completes exactly one line without a separator or trailing space.

The input elements and reduction internals are unnecessary for a question starting at the unformatted mean; the named result declaration and its formatting/emission line suffice.

Selected complete source lines in `Main.java`: 7, 8. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
