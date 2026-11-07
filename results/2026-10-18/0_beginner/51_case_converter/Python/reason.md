# Task B selection: 51_case_converter / Python

## Common answer requirements

Add ASCII-uppercase normalized words joined by underscores and append the fifth field to the existing per-identifier output.

## Source evidence

The retained snake assignment joins the shared normalized words with underscores; the print call gives the insertion point and formatting. ASCII uppercasing distributes over the join because it leaves underscores unchanged. Compute the fifth field from snake and append “, upper=” and its value to the same output line. Empty parts stay discarded by the existing normalization.

## Minimization

Reusing the already joined snake form avoids a second dependency on the split, empty-word filter, or other style calculations.

Selected complete lines of `main.py`: 13, 17. The prior excerpt measured 105 tokens; this excerpt measures 52 with `metric/tokenizer.py`.

## Current token measurement

Task A: **248 tokens**. Task B: **52 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
