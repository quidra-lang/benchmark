# Task B selection — TypeScript

## Answer requirements shared across languages

1. Reconstruct the complete SYSTEM settings path: fresh defaults, key=value parsing, unknown/duplicate handling, word and integer validation, explicit assignment and tlb/sets cross validation.
2. Identify the one frames default4 to change to8, and show explicit frames remains authoritative and later omitted frames uses the new default rather than previous state.
3. Trace creation of fresh frames, TLB, process and counter state from the resulting configuration, plus the SYSTEM output.

## Selected source locations

- `main.ts`: 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 769, 770, 771, 778, 779

## Evidence and language semantics

parseSettings spreads defaults into a fresh typed Settings value, validates each key and overwrites explicit frames before tlb%sets. New Simulation class fields reset maps/counters/flags; constructor allocates settings.frames null entries and settings.sets independent arrays. SYSTEM clears the previous instance then prints fresh settings in keys order. Change only the frames/frame_count default from4 to8. All explicit frames values remain subject to the existing1..16 validation and overwrite that default; the tlb/sets divisibility rule is unchanged. Since parsing and construction start afresh on each SYSTEM, SYSTEM frames=2 still allocates2 frames, and a later SYSTEM with frames omitted allocates8 rather than inheriting2. The output reports that newly resolved configuration. Empty collections, null/None pointers and language-defined zero initialization establish fresh process/frame/TLB/counter state without inspecting replacement algorithms or later memory accesses.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1511 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
