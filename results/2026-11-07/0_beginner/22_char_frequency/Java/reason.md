# Task B selection: 22_char_frequency / Java

Scan original case rather than its lowercase normalization, distinguish A..Z and a..z keys, and iterate uppercase buckets before lowercase buckets. The sentence contains P twice and p seven times, replacing the combined p count 9. Continue filtering only the two ASCII letter ranges and suppress zero counts; spaces and ! remain excluded.

Keep sentence, normalization/filter/key update and sorted output loop because all change together. Imports and culture setup do not add a needed fact.

Selected complete source lines in `Main.java`: 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
