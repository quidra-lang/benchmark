# Task B selection — JavaScript

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.js`: 13, 14, 15, 16, 17, 23, 24, 25, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 63, 120, 121, 122, 123, 124, 125, 153, 157, 158, 162, 164, 165, 166, 167, 169, 170, 171, 172, 174, 175, 176, 177, 178, 179, 181, 182, 183, 184, 187, 188, 189, 190, 191, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 219, 220, 221, 222, 223, 224, 419, 420, 462, 463, 464, 465, 466, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 497, 498

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. The Map entries and numeric time are separate Store properties. structuredClone recursively copies the database Map and its entries, so transaction and named snapshots do not alias current mutable entries. push/pop gives LIFO nested transactions; COMMIT only pops, whereas rollback and restore assign a saved database and call purge. RESTORE clones the retained snapshot, leaving it reusable. Number conversion and the integer notation identify the TTL/TICK values; the expiry comparison uses <=. The output helpers establish OK, (integer) counts, quoted strings and (nil).

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; standalone closing delimiters and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements.

The excerpt contains 2237 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
