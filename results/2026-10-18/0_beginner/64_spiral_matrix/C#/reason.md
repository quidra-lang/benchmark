# Task B selection: 64_spiral_matrix / C#

## Common answer requirements

Trace writes 6–12, the first occupied-cell turn, clockwise movement, and the final-write break.

## Supported analysis

With zero-based coordinates, 6 is at (0,5), 7–10 run down to (4,5), and 11–12 turn left to (4,4) and (4,3). The right step after 6 and down step after 10 are out of bounds. The first blocked in-bounds step is after 18 at (1,0), when (0,0) holds 1, so up turns right. The matrix initialization, movement offsets, bounds/occupancy tests and coordinate updates give the trace. After writing 30 the break comes before any proposed-cell computation.

The excerpt is copied verbatim from `Program.cs`, in source order. Retained source lines: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16.

## Minimization and alternatives

The final outer-loop close and display-only lines do not contribute any requested fact. Inner boundaries separating conditional turns from unconditional movement remain. The prior selection used 264 tokens; this selection uses 262 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
