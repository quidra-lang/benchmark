# Task B selection: 71_knapsack_01 / C++

## Common answer requirements

Locate the capacity, DP recurrence, reconstruction and output dependencies for weight 15 and the required tie order.

## Supported analysis

Set the limit to 15 at the binding or each repeated bound/lookup. For each take-or-skip state compare higher value, then lower actual weight, then lexicographically smaller increasing original positions, with a proper prefix first. Store enough reconstruction state to follow the chosen decision, because comparing adjacent scalar values discards ties. Preserve the maximum-value and weight lines and names in original order.

The excerpt is copied verbatim from `main.cpp`, in source order. Retained source lines: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28.

## Minimization and alternatives

The numerical item literals do not affect the modification design. The recurrence and reconstruction name the weight/value dependencies without retaining the unchanged item fixture or solving the modified instance. The prior selection used 509 tokens; this selection uses 434 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

## Current token measurement

Task A: **616 tokens**. Task B: **434 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
