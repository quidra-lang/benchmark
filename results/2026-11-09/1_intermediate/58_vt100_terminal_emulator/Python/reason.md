# Task B selection — Python

## Answer requirements shared across languages

1. Identify the CUP/HVP-only branch and both parameter sources with omitted/zero defaults.
2. Explain exchanging parameter roles for column;row while preserving origin-relative row addressing, row/column clamping and all other cursor-command semantics.

## Selected source locations

- `main.py`: 136, 137, 138, 139, 140, 141, 299, 300, 301, 525, 526, 527, 528, 651, 652, 653, 654, 655, 656

## Evidence and language semantics

H/f map to cursor_position and d to cursor_row. parameter defaults missing0; amount defaults first1, while address_row preserves DECOM offset and row bounds. Within H/f only, send max(second_parameter,1) through the existing row-address helper, and send max(first_parameter,1) through the width clamp for column. Preserve the helper's origin-mode top+row-1 and bottom/screen-height cap. J additionally retains its final zero-based adjustment. Do not alter the shared parameter/amount helper or swap the parsed array globally: other cursor branches shown keep their existing first-parameter use. The alternative of reading full CSI parsing, mode mutation and screen rendering is unnecessary to explain this local change.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 271 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
