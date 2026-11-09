# Task B selection — J

## Answer requirements shared across languages

1. Establish exact-symbol lookup before prefix decomposition, including the factor/dimension returned by a prefix match.
2. Connect DEFINE name rejection to the same resolver and explain why a name absent as an exact entry may still be taken.
3. Identify the restriction preventing prefixes on user-defined units.
4. Determine whether UNDEF of a referenced user unit changes another unit already defined from it, using stored factor/dimension and the deletion operation.

## Selected source locations

- `main.ijs`: 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 215, 553, 554, 556, 557, 558, 560, 561, 562, 563, 564, 568, 569, 570, 573, 574, 575, 576, 577

## Evidence and language semantics

i. tests the complete name before prefixes; prefix suffix search is confined to the first 42 names and Prefixable. DEFINE appends factor and dimension values to parallel arrays and appends zero to Prefixable. UNDEF applies a positional keep-mask to each array, retaining the other stored values.

## Minimization and alternatives

Compared with selecting the whole unit-expression parser or arithmetic library, the resolver plus DEFINE storage and UNDEF removal provide the required boundary directly. Argument-count validation, unrelated conversion/formatting commands, definition-list output and error cases unrelated to name resolution are omitted. Field declarations/constructors are retained only where positional construction or a custom constructor must be understood. The alternative of including only DEFINE is insufficient: it cannot establish exact-name precedence, prefix eligibility, or deletion behavior. Excerpt-only review: each of the four requirements is supported by the resolver ordering, rejection test, eligibility/storage fields, and targeted removal; no omitted Task A contract is used as evidence.

The excerpt contains 427 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
