# Task B selection — Python

## Answer requirements shared across languages

1. Reconstruct the complete SYSTEM settings path: fresh defaults, key=value parsing, unknown/duplicate handling, word and integer validation, explicit assignment and tlb/sets cross validation.
2. Identify the one frames default4 to change to8, and show explicit frames remains authoritative and later omitted frames uses the new default rather than previous state.
3. Trace creation of fresh frames, TLB, process and counter state from the resulting configuration, plus the SYSTEM output.

## Selected source locations

- `main.py`: 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 124, 125, 126, 127, 128, 129, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 200, 201, 202, 203, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 533, 534, 535, 536, 537, 538, 539, 540, 541

## Evidence and language semantics

parse_settings begins with {}, validates explicit pairs via setting_value, then setdefault fills omitted defaults, so explicit frames wins and a later SYSTEM cannot inherit it. Settings maps values to attributes; Simulation allocates None*settings.frames and Tlb creates fresh sets. Pager.start_system clears/replaces the simulation, resets event state and prints settings.describe(). Change only the frames/frame_count default from4 to8. All explicit frames values remain subject to the existing1..16 validation and overwrite that default; the tlb/sets divisibility rule is unchanged. Since parsing and construction start afresh on each SYSTEM, SYSTEM frames=2 still allocates2 frames, and a later SYSTEM with frames omitted allocates8 rather than inheriting2. The output reports that newly resolved configuration. Empty collections, null/None pointers and language-defined zero initialization establish fresh process/frame/TLB/counter state without inspecting replacement algorithms or later memory accesses.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1456 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
