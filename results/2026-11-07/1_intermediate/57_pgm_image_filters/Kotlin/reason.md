# Task B selection — Kotlin

## Answer requirements shared across languages

1. Locate maximum-gray conversion and range checks in NEW and PGM loading, widening only those ceilings from255 to1023.
2. Explain the adjacent integer conversion, nonnegative pixel validation and pixel/fill bounds0..M, retaining filter definitions.

## Selected source locations

- `main.kt`: 60, 61, 62, 63, 68, 75, 76, 77, 78, 79, 364, 365, 435, 436, 437, 438, 439

## Evidence and language semantics

Word checks and toInt conversions preserve integer values. Header maxval255 and NEW maxval in1..255 change, keeping pixel/fill0..M and IntArray storage. 1023 fits the shown general-purpose integer representations; byte text indexing does not imply byte pixel storage. Replace only the NEW/load maximum ceiling, retaining the lower bound1 and the per-pixel/fill range0..M. Decimal digit validation plus integer conversion continues to reject noninteger/negative PGM pixels. The alternative of replacing every255 or a shared filter constant was rejected because unrelated filter bounds are outside this proposal. Filter algorithms, image dimensions, and unrelated commands are omitted.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 416 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
