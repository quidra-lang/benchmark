# Task B selection — Dart

## Answer requirements shared across languages

1. Establish exact-symbol lookup before prefix decomposition, including the factor/dimension returned by a prefix match.
2. Connect DEFINE name rejection to the same resolver and explain why a name absent as an exact entry may still be taken.
3. Identify the restriction preventing prefixes on user-defined units.
4. Determine whether UNDEF of a referenced user unit changes another unit already defined from it, using stored factor/dimension and the deletion operation.

## Selected source locations

- `main.dart`: 110, 111, 112, 113, 120, 121, 122, 123, 124, 125, 367, 368, 369, 370, 371, 372, 373, 374, 375, 378, 552, 554, 555, 556, 558, 559, 562, 563, 566

## Evidence and language semantics

Exact symbol equality returns before the prefix loop. Prefix resolution rejects entries with a definition and disabled prefix flag. DEFINE stores evaluated value and dimension in final fields; removeAt removes an entry without invoking evaluation on the remaining units.

## Minimization and alternatives

Compared with selecting the whole unit-expression parser or arithmetic library, the resolver plus DEFINE storage and UNDEF removal provide the required boundary directly. Argument-count validation, unrelated conversion/formatting commands, definition-list output and error cases unrelated to name resolution are omitted. Field declarations/constructors are retained only where positional construction or a custom constructor must be understood. The alternative of including only DEFINE is insufficient: it cannot establish exact-name precedence, prefix eligibility, or deletion behavior. Excerpt-only review: each of the four requirements is supported by the resolver ordering, rejection test, eligibility/storage fields, and targeted removal; no omitted Task A contract is used as evidence.

The excerpt contains 484 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
