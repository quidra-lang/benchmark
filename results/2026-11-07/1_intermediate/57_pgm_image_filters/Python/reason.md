# Task B selection — Python

## Answer requirements shared across languages

1. Locate maximum-gray conversion and range checks in NEW and PGM loading, widening only those ceilings from255 to1023.
2. Explain the adjacent integer conversion, nonnegative pixel validation and pixel/fill bounds0..M, retaining filter definitions.

## Selected source locations

- `main.py`: 6, 8, 10, 101, 102, 103, 114, 122, 123, 124, 478, 479, 542, 543, 544, 545, 546, 562, 607

## Evidence and language semantics

Regex fullmatch and int establish integer values. MAX_MAXVAL currently feeds load and NEW but also BRIGHTNESS and change_maxval; split the NEW/load ceiling from the existing filter limit to preserve filter definitions. Pixels still satisfy digit-only text and <=M. 1023 fits the shown general-purpose integer representations; byte text indexing does not imply byte pixel storage. Replace only the NEW/load maximum ceiling, retaining the lower bound1 and the per-pixel/fill range0..M. Decimal digit validation plus integer conversion continues to reject noninteger/negative PGM pixels. The alternative of replacing every255 or a shared filter constant was rejected because unrelated filter bounds are outside this proposal. Filter algorithms, image dimensions, and unrelated commands are omitted.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 442 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
