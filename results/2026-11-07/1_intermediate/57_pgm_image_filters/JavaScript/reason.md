# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate maximum-gray conversion and range checks in NEW and PGM loading, widening only those ceilings from255 to1023.
2. Explain the adjacent integer conversion, nonnegative pixel validation and pixel/fill bounds0..M, retaining filter definitions.

## Selected source locations

- `main.js`: 3, 5, 157, 158, 159, 160, 164, 172, 173, 174, 175, 537, 538, 615, 616, 617, 618, 619

## Evidence and language semantics

Regexes enforce integral text before Number conversion, avoiding fractional Number acceptance. Load limit and NEW maxval<=255 change, retaining value<=maxval and fill0..M. 1023 fits the shown general-purpose integer representations; byte text indexing does not imply byte pixel storage. Replace only the NEW/load maximum ceiling, retaining the lower bound1 and the per-pixel/fill range0..M. Decimal digit validation plus integer conversion continues to reject noninteger/negative PGM pixels. The alternative of replacing every255 or a shared filter constant was rejected because unrelated filter bounds are outside this proposal. Filter algorithms, image dimensions, and unrelated commands are omitted.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 467 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
