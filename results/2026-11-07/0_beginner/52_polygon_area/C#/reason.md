# Task B selection: 52_polygon_area / C#

With zero vertices, cross and perimeter start at zero and the edge range is empty. Neither vertices[0] nor last-to-first modulo access is evaluated; there is no explicit rejection or earlier first-element read. Formatting therefore receives area 0.0 and perimeter 0.000 for polygon 1 rather than raising an empty-input failure.

Keep local defaults, loop entry/bound, first access and output. The loop body beyond its access cannot run for empty input, and nonempty polygon data is unnecessary to establish this path.

Selected complete source lines in `Program.cs`: 13, 14, 15, 16, 17, 18, 23. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
