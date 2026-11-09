# Task B selection — C

## Answer requirements shared across languages

1. Trace requested payload size and alignment through rounded internal size, free placeable-block selection and the unchanged leading-fragment rule.
2. Identify trailing split and used-block-size changes for threshold24, explain remainders16 and24, and derive the NEXT rover from actual used extent.
3. Explain why BUDDY splitting and its size rounding are unchanged.

## Selected source locations

- `main.c`: 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 357, 363

## Evidence and language semantics

required rounds payload to8-byte units plus8 header, with mode5 power-of-two minimum32. allocate aligns payload start, retains leading16 rule, ranks free placeable blocks, splits BUDDY halves separately, and updates NEXT rover from actual used end. Only non-BUDDY trailing comparison at138 changes. Only the free-list trailing remainder threshold changes from16 to24. Let required internal size be S and available aligned suffix be A. A-S=16 is now absorbed, so used size A=S+16 and no tail exists; A-S=24 is split, so used size S and a24-byte free tail remains. NEXT rover is the end of that actual used block, wrapping at heap size: it advances16 farther in the absorbed16 case, and points at the tail in the24 case. Preserve payload rounding/alignment, free-fit choice, leading-fragment16 rule and separate BUDDY powers/halves. Where one condition controls both size and split, edit that one; where two equivalent expressions exist, keep both consistent. Global MIN_BLOCK replacement and realloc/coalescing code were considered and excluded because this proposal targets allocation trailing splitting, not every16-byte rule.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1241 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
