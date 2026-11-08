# Task B selection — Lua

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.lua`: 9, 10, 11, 12, 19, 20, 38, 39, 40, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 102, 103, 104, 175, 176, 177, 178, 179, 180, 207, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 262, 263, 264, 269, 270, 271, 272, 273, 274, 275, 276, 277, 300, 301, 413, 430, 431, 432, 433, 434, 435, 467, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. Lua tables are references; copy explicitly builds a new key-entry table. The entries themselves are shared, but the selected put creates a replacement entry and purge deletes only a key from the active table. No traced operation mutates an existing entry, so shallow copying is sufficient for this scenario without an unsupported language immutability claim. table.remove consumes the newest transaction save only; named restore copies and retains its saved table. time belongs to the Store separately and is unchanged by database restoration. The token parser, argument slicing, dynamic handler dispatch, numeric parser and reply emitters close the observable path.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; necessary internal control boundaries are retained; redundant outer declaration frames and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements. The bare-token loop ends before the completed argument list is returned. Necessary option-loop, command-arm, transaction/TICK and main input/error boundaries preserve subsequent command reachability and reply order. A brace or end on its own is retained when it establishes such a boundary; Python and Quidra retain the corresponding indentation. The quoted-token path, unrelated commands and outer declaration framing remain excluded.

The excerpt contains 2586 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
