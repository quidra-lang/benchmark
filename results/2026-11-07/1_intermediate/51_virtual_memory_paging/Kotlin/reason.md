# Task B selection — Kotlin

## Answer requirements shared across languages

1. Reconstruct the complete SYSTEM settings path: fresh defaults, key=value parsing, unknown/duplicate handling, word and integer validation, explicit assignment and tlb/sets cross validation.
2. Identify the one frames default4 to change to8, and show explicit frames remains authoritative and later omitted frames uses the new default rather than previous state.
3. Trace creation of fresh frames, TLB, process and counter state from the resulting configuration, plus the SYSTEM output.

## Selected source locations

- `main.kt`: 4, 5, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 615, 616, 617, 625, 626

## Evidence and language semantics

Config default frames4 is recreated by settings for each SYSTEM; explicit frames validates and assigns before the cross-check. Simulation field initializers allocate c.frames null entries and c.sets independent lists, empty maps/history, zero counts and fixed sentinels. SYSTEM clears the predecessor and emits c.description(). Change only the frames/frame_count default from4 to8. All explicit frames values remain subject to the existing1..16 validation and overwrite that default; the tlb/sets divisibility rule is unchanged. Since parsing and construction start afresh on each SYSTEM, SYSTEM frames=2 still allocates2 frames, and a later SYSTEM with frames omitted allocates8 rather than inheriting2. The output reports that newly resolved configuration. Empty collections, null/None pointers and language-defined zero initialization establish fresh process/frame/TLB/counter state without inspecting replacement algorithms or later memory accesses.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1559 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
