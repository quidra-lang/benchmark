# Task B selection — Go

## Answer requirements shared across languages

1. Establish exact-symbol lookup before prefix decomposition, including the factor/dimension returned by a prefix match.
2. Connect DEFINE name rejection to the same resolver and explain why a name absent as an exact entry may still be taken.
3. Identify the restriction preventing prefixes on user-defined units.
4. Determine whether UNDEF of a referenced user unit changes another unit already defined from it, using stored factor/dimension and the deletion operation.

## Selected source locations

- `main.go`: 499, 520, 522, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 541, 578, 580, 582, 584, 585, 587, 588, 590, 591, 592, 595

## Evidence and language semantics

Exact lookup returns first; the prefix suffix lookup is restricted to db.units[:42], the builtin portion. DEFINE appends a computed quantity with prefix=false. Rebuilding the slice around the deleted index preserves all other quantity values.

## Minimization and alternatives

Compared with selecting the whole unit-expression parser or arithmetic library, the resolver plus DEFINE storage and UNDEF removal provide the required boundary directly. Argument-count validation, unrelated conversion/formatting commands, definition-list output and error cases unrelated to name resolution are omitted. Field declarations/constructors are retained only where positional construction or a custom constructor must be understood. The alternative of including only DEFINE is insufficient: it cannot establish exact-name precedence, prefix eligibility, or deletion behavior. Excerpt-only review: each of the four requirements is supported by the resolver ordering, rejection test, eligibility/storage fields, and targeted removal; no omitted Task A contract is used as evidence.

The excerpt contains 779 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
