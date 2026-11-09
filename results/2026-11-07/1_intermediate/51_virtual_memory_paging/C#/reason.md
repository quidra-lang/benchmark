# Task B selection — C#

## Answer requirements shared across languages

1. Reconstruct the complete SYSTEM settings path: fresh defaults, key=value parsing, unknown/duplicate handling, word and integer validation, explicit assignment and tlb/sets cross validation.
2. Identify the one frames default4 to change to8, and show explicit frames remains authoritative and later omitted frames uses the new default rather than previous state.
3. Trace creation of fresh frames, TLB, process and counter state from the resulting configuration, plus the SYSTEM output.

## Selected source locations

- `Program.cs`: 7, 8, 19, 20, 21, 23, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 613, 614, 615, 622, 623

## Evidence and language semantics

Each Settings call constructs a fresh Config whose Frames field is4; explicit frames is range-checked and assigned. New Simulation uses c.Frames null entries and c.Sets fresh lists; field initializers plus CLR zero initialization reset process maps, flags and counters. The caller nulls the old system and prints the fresh config. Change only the frames/frame_count default from4 to8. All explicit frames values remain subject to the existing1..16 validation and overwrite that default; the tlb/sets divisibility rule is unchanged. Since parsing and construction start afresh on each SYSTEM, SYSTEM frames=2 still allocates2 frames, and a later SYSTEM with frames omitted allocates8 rather than inheriting2. The output reports that newly resolved configuration. Empty collections, null/None pointers and language-defined zero initialization establish fresh process/frame/TLB/counter state without inspecting replacement algorithms or later memory accesses.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1823 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
