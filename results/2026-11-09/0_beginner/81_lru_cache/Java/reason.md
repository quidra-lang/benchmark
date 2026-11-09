# Task B selection: 81_lru_cache / Java

Before the fourth access the order is C A B; hitting B removes and reinserts it at the front, giving B C A and one hit. D then misses, evicts tail A and yields D B C. List removal/insertion mutate the same cache storage that the next iteration reads; hit/miss counters and status update accordingly. The access string is independent immutable storage and never aliases cache ordering.

Keep initial cache/counters, access source and complete per-access update/output path. No unrelated program scaffolding or standard collection implementation is needed.

Selected complete source lines in `Main.java`: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
