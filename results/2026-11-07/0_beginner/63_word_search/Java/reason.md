# Task B selection: 63_word_search / Java

word comes from the word loop, r/c from the start-cell loops, and d selects E at offset dr=0,dc=1. The candidate cell is r+k*dr[d], c+k*dc[d]; its comparison reads the enclosing board and current word. C#/Kotlin lambdas capture those enclosing local values; Java performs the same comparisons inline. This is local scope resolution, not a separate helper with hidden parameters.

Keep the board binding declaration, direction-offset declarations, binding headers and comparison block. Remaining board literal rows, result formatting, traversal completion and successful-result handling do not establish these local bindings.

Selected complete source lines in `Main.java`: 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
