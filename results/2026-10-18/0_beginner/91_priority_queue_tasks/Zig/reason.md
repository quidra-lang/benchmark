# Task B selection — 91_priority_queue_tasks / Zig

Keep std.PriorityQueue ordering by smaller numeric priority. In compare, use lexicographic byte order on the stored task names for equal priority. The same comparator is wired into the heap serving both pop call sites. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 3, 5, 6, 7, 8, 9, 34, 46, 47, 51.

With the benchmark tokenizer, this selection measures 223 tokens; the previous selection measured 203. The full source is 807 tokens.
