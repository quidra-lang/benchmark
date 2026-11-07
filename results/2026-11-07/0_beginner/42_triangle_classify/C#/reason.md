# Task B selection: 42_triangle_classify / C#

Split a+b<=c into equality and strict less-than before side/angle classification, with both rejected cases bypassing the valid path. The supplied (3,8,5), sorted to (3,5,8), reaches degenerate; (2,9,4) remains not a triangle. Other valid sets continue into unchanged side and angle comparisons/output.

Keep supplied sets, ordered-side derivation, current early exit and the existing classification continuation. Other setup and original-order prefix construction do not locate this boundary change.

Selected complete source lines in `Program.cs`: 8, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
