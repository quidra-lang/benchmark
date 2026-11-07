# Task B selection: 46_word_frequency / C#

Normalized cat occurrences share one string key. C# grouping then Count, or Kotlin groupingBy.eachCount, yields one for a first occurrence and two for the second using library-managed aggregation. Java merge(word,1,sum) inserts one when absent, then replaces its immutable Integer value with old+1 in the same mutable map. No ranking operation is involved.

The count construction/update and relevant storage definition suffice; the long sentence and ranking/printing add no fact to the local absent-key/update semantics.

Selected complete source lines in `Program.cs`: 9, 10, 11. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
