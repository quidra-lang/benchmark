# Task B selection: 62_edit_distance / C#

At prefixes 2,2, a[1] and b[1] are both i, so replacement cost is zero. The deletion/insertion candidates are neighboring prefix costs plus one; the diagonal candidate uses that zero cost and wins at 1. Math.Min/minOf evaluates its arguments ordinarily: matching changes the diagonal cost, not control flow that skips the other candidate computations.

Keep DP dimensions/base states, iteration and the entire cost/min expression so prefix meaning and eager candidate evaluation are explicit. Input strings are supplied by the question; final output is irrelevant.

Selected complete source lines in `Program.cs`: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
