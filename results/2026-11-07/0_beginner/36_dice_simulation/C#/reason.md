# Task B selection: 36_dice_simulation / C#

Seed 12345 advances to 595905495 and 1558181227 for the first pair, mapping by state mod 6 + 1 to dice 4 and 2, sum 6. Exactly 1000 trials each advance twice and increment one zero-initialized sum bucket. Sum output runs 2..12, then the most-frequent line; best starts at 2 and only strict improvements replace it, retaining the smaller sum on a tie.

All simulation-state, bucket, loop and final-selection/output dependencies are retained; no individual state trace or unrelated setup is included.

Selected complete source lines in `Program.cs`: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
