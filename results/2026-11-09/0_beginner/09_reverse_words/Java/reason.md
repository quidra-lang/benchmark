# Task B selection: 09_reverse_words / Java

The first reversal operates on individual character units, turning the end line and its preceding space into enil followed by a space. The second splits on spaces into whole words, reverses word order and joins with a single-space separator, leaving line intact as its first word.

The two adjacent transformations establish both units and joining behavior. The question supplies the final word and preceding space, so the full sentence literal is unnecessary; standard string/sequence reversal semantics avoid including library code.

Selected complete source lines in `Main.java`: 6, 7. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
