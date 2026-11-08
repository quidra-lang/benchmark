# Task B selection — Rust

## Answer requirements shared across languages

1. Trace requested payload size and alignment through rounded internal size, free placeable-block selection and the unchanged leading-fragment rule.
2. Identify trailing split and used-block-size changes for threshold24, explain remainders16 and24, and derive the NEXT rover from actual used extent.
3. Explain why BUDDY splitting and its size rounding are unchanged.

## Selected source locations

- `main.rs`: 16, 33, 39, 40, 41, 42, 43, 44, 45, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102

## Evidence and language semantics

required uses div_ceil8+header and BUDDY power2 minimum32. allocate ranks aligned free fits, retains leading16 and BUDDY halves, and changes only remainder>=16 at94. NEXT rover uses block.end after actual used size is set. Only the free-list trailing remainder threshold changes from16 to24. Let required internal size be S and available aligned suffix be A. A-S=16 is now absorbed, so used size A=S+16 and no tail exists; A-S=24 is split, so used size S and a24-byte free tail remains. NEXT rover is the end of that actual used block, wrapping at heap size: it advances16 farther in the absorbed16 case, and points at the tail in the24 case. Preserve payload rounding/alignment, free-fit choice, leading-fragment16 rule and separate BUDDY powers/halves. Where one condition controls both size and split, edit that one; where two equivalent expressions exist, keep both consistent. Global MIN_BLOCK replacement and realloc/coalescing code were considered and excluded because this proposal targets allocation trailing splitting, not every16-byte rule.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1207 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
