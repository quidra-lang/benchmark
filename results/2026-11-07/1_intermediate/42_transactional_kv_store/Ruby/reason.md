# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.rb`: 8, 9, 10, 11, 35, 37, 38, 39, 40, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 78, 79, 82, 83, 84, 85, 86, 87, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 215, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 231, 232, 233, 234, 235, 236, 237, 242, 243, 244, 245, 246, 247, 248, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 285, 286, 287, 288, 289, 290, 297, 298, 299, 300, 301, 302, 325, 326, 327, 328, 513, 514, 529, 530, 531, 532, 533, 534, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 599, 600, 601, 602, 603, 606, 607, 608

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. Ruby Hash#dup copies the key-entry mapping. Entry and TextValue are immutable Data records, and TextValue duplicates and freezes its String, so shallow map copies suffice for this text-only scenario. Each SET installs a new Entry. The transaction array pop discards one saved map; named restore duplicates a saved map without removing the name. The independent @time instance variable is not restored, so purge removes expiry <= @time again. The selected parser, command specification, dynamic dispatch and formatting connect this ownership model to the observable trace.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; necessary internal control boundaries are retained; redundant outer declaration frames and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements. The bare-token loop ends before the completed argument list is returned. Necessary option-loop, command-arm, transaction/TICK and main input/error boundaries preserve subsequent command reachability and reply order. A brace or end on its own is retained when it establishes such a boundary; Python and Quidra retain the corresponding indentation. The quoted-token path, unrelated commands and outer declaration framing remain excluded.

The excerpt contains 1965 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
