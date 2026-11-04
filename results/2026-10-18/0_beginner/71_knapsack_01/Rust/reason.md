# Task B selection: 71_knapsack_01 / Rust

## Common answer requirements

Locate the capacity, DP recurrence, reconstruction and output dependencies for weight 15 and the required tie order.

## Supported analysis

Set the limit to 15 at the binding or each repeated bound/lookup. For each take-or-skip state compare higher value, then lower actual weight, then lexicographically smaller increasing original positions, with a proper prefix first. Store enough reconstruction state to follow the chosen decision, because comparing adjacent scalar values discards ties. Preserve the maximum-value and weight lines and names in original order.

The excerpt is copied verbatim from `main.rs`, in source order. Retained source lines: 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29.

## Minimization and alternatives

The numerical item literals do not affect the modification design. The recurrence and reconstruction name the weight/value dependencies without retaining the unchanged item fixture or solving the modified instance. The prior selection used 492 tokens; this selection uses 415 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
