# Task B selection — Zig

## Answer requirements shared across languages

1. Establish exact-symbol lookup before prefix decomposition, including the factor/dimension returned by a prefix match.
2. Connect DEFINE name rejection to the same resolver and explain why a name absent as an exact entry may still be taken.
3. Identify the restriction preventing prefixes on user-defined units.
4. Determine whether UNDEF of a referenced user unit changes another unit already defined from it, using stored factor/dimension and the deletion operation.

## Selected source locations

- `main.zig`: 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 724, 726, 727, 728, 729, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 743, 744, 745, 746, 747, 748, 749, 750, 751, 753, 754

## Evidence and language semantics

The exact loop returns the stored quantity first. The prefix fallback reads builtins, never newly appended units. DEFINE stores the calculated Quantity with .prefix=false separately from definition text. UNDEF compacts registry entries by value and decrements the length; other quantities remain unchanged.

## Minimization and alternatives

Compared with selecting the whole unit-expression parser or arithmetic library, the resolver plus DEFINE storage and UNDEF removal provide the required boundary directly. Argument-count validation, unrelated conversion/formatting commands, definition-list output and error cases unrelated to name resolution are omitted. Field declarations/constructors are retained only where positional construction or a custom constructor must be understood. The alternative of including only DEFINE is insufficient: it cannot establish exact-name precedence, prefix eligibility, or deletion behavior. Excerpt-only review: each of the four requirements is supported by the resolver ordering, rejection test, eligibility/storage fields, and targeted removal; no omitted Task A contract is used as evidence.

The excerpt contains 803 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
