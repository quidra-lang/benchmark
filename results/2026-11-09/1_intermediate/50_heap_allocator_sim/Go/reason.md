# Task B selection — Go

## Answer requirements shared across languages

1. Trace requested payload size and alignment through rounded internal size, free placeable-block selection and the unchanged leading-fragment rule.
2. Identify trailing split and used-block-size changes for threshold24, explain remainders16 and24, and derive the NEXT rover from actual used extent.
3. Explain why BUDDY splitting and its size rounding are unchanged.

## Selected source locations

- `main.go`: 61, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 516

## Evidence and language semantics

requiredLength handles8-byte rounding and BUDDY power2. placement/choose retain leading minBlock and rank aligned free fits. carve205 alone controls trailing split and used length; allocate updates NEXT rover from final end and uses halve only for BUDDY. Only the free-list trailing remainder threshold changes from16 to24. Let required internal size be S and available aligned suffix be A. A-S=16 is now absorbed, so used size A=S+16 and no tail exists; A-S=24 is split, so used size S and a24-byte free tail remains. NEXT rover is the end of that actual used block, wrapping at heap size: it advances16 farther in the absorbed16 case, and points at the tail in the24 case. Preserve payload rounding/alignment, free-fit choice, leading-fragment16 rule and separate BUDDY powers/halves. Where one condition controls both size and split, edit that one; where two equivalent expressions exist, keep both consistent. Global MIN_BLOCK replacement and realloc/coalescing code were considered and excluded because this proposal targets allocation trailing splitting, not every16-byte rule.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1448 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
