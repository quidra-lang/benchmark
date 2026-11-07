# Task B selection: 54_max_subarray / Kotlin

The source already initializes current and best from values[0], representing a nonempty candidate. For [-6,-3,-9], restart after negative current chooses -3 at index 1; the final restart gives -9 without improving best. The result is max sum -3 at [1, 1], so no zero/empty initialization change is required.

The extension supplies its own array, so existing examples are unnecessary. Initialization, restart/extend recurrence, strict best update and range output establish the whole dependency.

Selected complete source lines in `main.kt`: 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
