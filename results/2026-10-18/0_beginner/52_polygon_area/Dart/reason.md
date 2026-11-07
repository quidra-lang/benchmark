# Task B selection: 52_polygon_area / Dart

## Common answer requirements

Identify both closing-edge calculations, evaluate that edge for polygon 2, and explain the final area and perimeter accumulation order.

## Source evidence

The first two data rows identify polygon 2 and its endpoints. The successor wraps from the last index to the first, and the same pair feeds both updates. The edge (8,2) → (2,1) adds 8×1 − 2×2 = 4 to the signed shoelace sum and √((8−2)²+(2−1)²) = √37 to the perimeter. That square root is added to the running floating-point perimeter after all earlier edges because the code iterates vertices in order. The completed shoelace sum is converted to its absolute magnitude and divided by two.

## Minimization

Only enough input rows to identify polygon 2 are needed; a separate third polygon contributes no evidence. The selected area argument or assignment contains the normalization; extra print wrappers or trailing scopes add no calculation.

Selected complete lines of `main.dart`: 1, 4–6, 8–17, 19. The prior excerpt measured 387 tokens; this excerpt measures 376 with `metric/tokenizer.py`.

## Current token measurement

Task A: **455 tokens**. Task B: **375 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
