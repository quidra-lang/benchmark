# Task B selection — C++

## Answer requirements shared across languages

1. Reconstruct the complete SYSTEM settings path: fresh defaults, key=value parsing, unknown/duplicate handling, word and integer validation, explicit assignment and tlb/sets cross validation.
2. Identify the one frames default4 to change to8, and show explicit frames remains authoritative and later omitted frames uses the new default rather than previous state.
3. Trace creation of fresh frames, TLB, process and counter state from the resulting configuration, plus the SYSTEM output.

## Selected source locations

- `main.cpp`: 16, 17, 47, 48, 49, 50, 51, 52, 53, 54, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 707, 708, 709, 716, 717

## Evidence and language semantics

Fresh Config defaults frames to4, then settings independently validates and overwrites explicit keys. The constructor sizes null frames from c.frames, creates sets, and initializes fresh maps/counters. SYSTEM resets its old pointer before parsing and prints description from the new configuration. Change only the frames/frame_count default from4 to8. All explicit frames values remain subject to the existing1..16 validation and overwrite that default; the tlb/sets divisibility rule is unchanged. Since parsing and construction start afresh on each SYSTEM, SYSTEM frames=2 still allocates2 frames, and a later SYSTEM with frames omitted allocates8 rather than inheriting2. The output reports that newly resolved configuration. Empty collections, null/None pointers and language-defined zero initialization establish fresh process/frame/TLB/counter state without inspecting replacement algorithms or later memory accesses.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1808 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
