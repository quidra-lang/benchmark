# Task B selection — Rust

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.rs`: 11, 12, 13, 26, 27, 28, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 58, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 88, 90, 91, 92, 93, 94, 95, 96, 97, 98, 192, 193, 194, 195, 199, 200, 201, 202, 203, 209, 214, 215, 216, 217, 218, 219, 242, 243, 244, 250, 251, 252, 253, 254, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 286, 287, 288, 289, 290, 291, 292, 561, 562, 563, 564, 565, 566, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 591, 592, 593, 594, 595, 596, 597, 598, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. The derived Clone implementations on Value and Entry, with String and BTreeMap ownership, make database.clone() an independent copy for the traced strings and expiry values; no Rc/RefCell alias is introduced. Derived Default initializes time to zero. Vec::pop returns the newest saved database, while snapshot get plus clone preserves the named copy. purge retains only no-expiry or expiry > time records, equivalently removing expired deadlines at <= time. Integer parsing, command arities and the Display arms connect accepted commands to OK, integer counts, strings and nil. A borrow alone would not prove copy independence, which is why the derived data declarations and clone sites are selected.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; standalone closing delimiters and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements.

The excerpt contains 3232 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
