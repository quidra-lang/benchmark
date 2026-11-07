# Task B selection: 89_dijkstra / Java

Replace int.MaxValue / Integer.MAX_VALUE / Int.MAX_VALUE in distance initialization with 1000, retaining distance[0]=0. Seven vertices and positive edge weights at most 9 bound a simple shortest path by 6*9=54, safely below 1000; cycles cannot improve positive-weight paths.

The sentinel/source assignment and graph size/edge weights establish this default-only change. Relaxation, predecessor reconstruction and output remain unaffected and are omitted.

Selected complete source lines in `Main.java`: 8, 9, 10, 15, 16, 18. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
