# Task B selection — C++

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.cpp`: 16, 17, 18, 19, 20, 21, 22, 23, 34, 35, 36, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 59, 60, 61, 62, 63, 64, 65, 66, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 114, 193, 194, 195, 196, 197, 198, 199, 200, 228, 232, 233, 234, 238, 239, 240, 241, 243, 244, 245, 246, 247, 248, 250, 251, 252, 253, 254, 255, 256, 257, 263, 264, 265, 266, 267, 268, 269, 270, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 301, 302, 303, 304, 305, 331, 332, 544, 571, 572, 573, 574, 575, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 646, 647, 648, 656, 657, 658, 659, 660, 661, 662, 663

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. Database is a value-owned std::map of Records containing std::variant values and optional expiry; for the traced string keys ordinary map/variant/string copying provides independent values. push_back and snapshot insert_or_assign copy the database. Moving the last transaction into the current database consumes only that stack entry; named restore copies found->second and leaves its map entry retained. The selected time field and restore code establish that logical time is not restored; purge uses <= and outputs the deletion count. The supplied output functions explain quoting and nil.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; standalone closing delimiters and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements.

The excerpt contains 3319 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
