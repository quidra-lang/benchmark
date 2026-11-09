# Task B selection — Ruby

## Answer requirements shared across languages

1. Identify the CUP/HVP-only branch and both parameter sources with omitted/zero defaults.
2. Explain exchanging parameter roles for column;row while preserving origin-relative row addressing, row/column clamping and all other cursor-command semantics.

## Selected source locations

- `main.rb`: 94, 95, 96, 293, 294, 324, 325, 326

## Evidence and language semantics

Missing params default0, n=max1; address preserves DECOM offset/clamp. H/f is one paired assignment, while G and d independently use first-parameter semantics. Within H/f only, send max(second_parameter,1) through the existing row-address helper, and send max(first_parameter,1) through the width clamp for column. Preserve the helper's origin-mode top+row-1 and bottom/screen-height cap. J additionally retains its final zero-based adjustment. Do not alter the shared parameter/amount helper or swap the parsed array globally: other cursor branches shown keep their existing first-parameter use. The alternative of reading full CSI parsing, mode mutation and screen rendering is unnecessary to explain this local change.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 179 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
