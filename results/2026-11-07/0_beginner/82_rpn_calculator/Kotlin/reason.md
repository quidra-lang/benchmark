# Task B selection: 82_rpn_calculator / Kotlin

Each expression starts with empty stack and no error. In expression 2, -17 and 5 divide as a/b after popping b first, truncating to -3; 4 and -3 multiply to -12, then -3-(-12)=9. Operator guards detect fewer than two operands and zero b, breaking before further pushes; final size!=1 detects leftovers only without an earlier error. Stack updates and error/result selection establish one final result or error.

Keep only the input line containing expression 2 and the complete shared evaluator path, including all error exits. Other expression data and entry-point scaffolding add no fact.

Selected complete source lines in `main.kt`: 2, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
