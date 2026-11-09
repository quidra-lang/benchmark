# Task B selection: 77_langtons_ant / C#

Retain incoming position/direction and board color, apply turn then invert the current cell, then compute proposed row/column without modulo wrapping. Commit both proposed coordinates only if both lie in 0..10; otherwise retain both old coordinates. For an upward proposal from row 0, proposed row -1 is rejected after turn/flip, so those effects survive while position remains.

Only one-step state initialization/offsets and turn/flip/movement operation are required. Rendering and black-cell counting do not affect the movement contract.

Selected complete source lines in `Program.cs`: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
