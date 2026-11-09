# Task B selection — Go

## Answer requirements shared across languages

1. Explain numeric equality of signed zero versus the distinct total-order keys of their encodings.
2. Trace NEXTUP and NEXTDOWN for +0, -0, the least positive subnormal and the least negative subnormal, including each resulting zero sign.
3. Identify flags for these cases and for quiet/signaling NaNs, and contrast unordered numeric comparison with total ordering and NaN-producing neighbor operations.

## Selected source locations

- `main.go`: 12, 13, 15, 16, 67, 69, 70, 71, 72, 73, 74, 75, 76, 288, 289, 290, 291, 298, 299, 300, 301, 302, 306, 307, 308, 311, 312, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 342, 607, 608, 609, 610, 611, 612, 614, 615, 616, 617, 618, 619, 620, 621, 622, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 855, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909

## Evidence and language semantics

The selected representation predicates and sign manipulation identify +0 as pattern 0, -0 as the sign mask S, and the adjacent subnormals as 1 and S+1. The total key gives -0 key -1 and +0 key 0, whereas the numeric comparison explicitly returns EQ for two zeros. NEXTUP maps either zero to 1, maps 1 to 2, and maps S+1 to S (-0). NEXTDOWN, implemented by sign reflection around NEXTUP, maps either zero to S+1, maps 1 to 0 (+0), and maps S+1 to S+2. Thus crossing from a nonzero subnormal to zero preserves the side of approach. Neighbor paths use zero flags for all of these exact representable steps; they do not call rounding and do not raise underflow/inexact. NaNs are intercepted: quiet NaNs yield a canonical quiet NaN without flags and signaling NaNs additionally raise invalid. COMPARE instead reports UN numerically for any NaN while still producing a key-based total relation, and raises invalid only for signaling NaNs. Integer masking, shifts, comparisons and conditional branch semantics suffice; no floating-point host comparison or arithmetic implementation is assumed.

## Minimization and alternatives

Reviewed both command dispatch and the neighbor helper. Kept only representation/NaN predicates, the ordering branch, the two neighbor paths and their flag default. Arithmetic rounding, operand text parsing, unrelated ULP handling, formatting implementations, format registry and I/O cannot change the requested pattern-level trace and are omitted. Using only the zero-equality conditional is smaller but loses the distinct total keys; using only the neighbor helper loses NaN interception and flags. A TABLE dump or full decoder would cost more than the sign/field predicates. Structural closing lines and unused branches are omitted where their information is already established by the selected headers/conditions. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1205 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
