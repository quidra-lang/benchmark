# Task B selection: 21_remove_duplicates / Java

Input 12 is first seen at index 0 and repeats at 2 and 13; only the first is retained. HashSet.Add filtering / LinkedHashSet insertion / distinct preserves first appearance, yielding 12 5 8 3 20 15 7 9 and then removed: 7. Equality detects repeats rather than a numeric ordering comparison.

Both input and retention operation are necessary for the exact sequence, while both output constructions establish the two lines. Library insertion/distinct semantics replace a custom deduplication trace.

Selected complete source lines in `Main.java`: 6, 7, 8, 9, 10, 11, 12. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
