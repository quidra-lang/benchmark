# Task B selection — Python

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.py`: 7, 9, 22, 23, 26, 27, 28, 29, 30, 31, 42, 43, 44, 45, 49, 56, 57, 58, 59, 60, 79, 80, 81, 82, 83, 84, 85, 93, 94, 95, 96, 97, 98, 99, 102, 103, 104, 105, 106, 107, 108, 109, 131, 132, 133, 134, 135, 136, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 329, 330, 331, 332, 333, 334, 335, 336, 337, 340, 341, 345, 346, 347, 348, 349, 350, 351, 352, 410, 415, 416, 417, 418, 419, 420, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 436, 437, 438, 439, 440, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 479, 480, 481, 482, 483, 484, 485, 486, 489, 491, 492, 493, 905, 906, 907, 908, 909, 910, 936, 937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 966, 967, 968, 969, 970

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. Python dictionaries and Entry objects are mutable references, so copying the dictionary alone would be insufficient. The selected copy_database comprehension calls Entry.copy; that constructs fresh Entry objects and safely reuses immutable strings for the scenario. BEGIN stores these independent dictionaries, COMMIT pops only the top save, rollback consumes its save, and RESTORE copies the named dictionary without deleting it. Only database is reassigned: now and snapshots remain separate, and remove_expired immediately removes absolute deadlines <= now. The dispatch, TTL parsing and reply functions fully determine the trace outputs.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; standalone closing delimiters and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements.

The excerpt contains 2490 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
