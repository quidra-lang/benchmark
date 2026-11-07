# Task B selection: 40_binary_search / C#

Initial bounds 0 and 15 give midpoint (0+15)/2 = 7 by integer division. values[7] is 31, whereas the recorded probe is the midpoint itself (or its decimal text), not 31 or ordinal 8. Array subscripting uses zero-based positions.

The array, bounds, midpoint, record operation and indexed comparison suffice. Later bound updates and final search output are outside the first-probe question.

Selected complete source lines in `Program.cs`: 7, 10, 14, 15, 16. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
