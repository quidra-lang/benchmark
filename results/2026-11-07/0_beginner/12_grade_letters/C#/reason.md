# Task B selection: 12_grade_letters / C#

Five integer array entries initially default to zero; D is index 3 and none of the supplied scores enters 60..69. Reusing the same storage for a second report requires filling all five entries with zero before counting again, or allocating a new zero-filled array. The indexed increment and final indexed read then report D: 0 rather than accumulating earlier counts.

Retain grade/index mapping, zero initialization, the scores/threshold decision, increment and report lookup. Per-score printing is not required for resetting count storage.

Selected complete source lines in `Program.cs`: 6, 7, 8, 10, 11, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
