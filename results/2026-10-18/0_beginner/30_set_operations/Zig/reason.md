# Task B selection — 30_set_operations / Zig

## Common answer requirements

Locate the third, labeled set-difference result and change only its membership direction to B minus A.

## Source evidence

Reverse the operand roles in the selected difference operation or predicate. Keep its existing result position, label and surrounding processing. Where a shared dispatcher selects operations by index, the selected label and dispatch bindings associate its third case with the required result.

## Minimization

Selected complete lines of `main.zig`: L13, L14, L16, L17, L20. Only membership for the third result changes. Its unchanged output, other result expressions, and sorting code do not need a separate edit. Keep type or iteration evidence only when it identifies the operation or the candidate domain needed to reverse it.

The selected excerpt measures **120 tokens** with `metric/tokenizer.py`.

## Current token measurement

Task A: **517 tokens**. Task B: **120 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
