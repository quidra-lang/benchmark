# Task B selection — TypeScript

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.ts`: 12, 13, 14, 32, 33, 34, 35, 42, 43, 44, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 83, 84, 141, 142, 143, 144, 145, 146, 174, 178, 179, 182, 183, 184, 185, 188, 189, 190, 191, 193, 194, 195, 196, 198, 199, 200, 201, 202, 203, 205, 206, 207, 208, 211, 212, 213, 214, 215, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 243, 244, 245, 246, 247, 248, 271, 452, 453, 495, 496, 497, 498, 499, 500, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 533, 534

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. The Database/StoredEntry declarations establish Map entries carrying nullable absolute expiry; private time, stack and snapshots are distinct fields. TypeScript readonly and private annotations do not create deep snapshots, so the selected structuredClone calls are essential. structuredClone supplies independent Map/entry copies; LIFO pop discards only the newest transaction, and RESTORE clones rather than consumes the named copy. Purge removes expiry <= time and returns the count; command and reply code connects this to the displayed values.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; necessary internal control boundaries are retained; redundant outer declaration frames and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements. The bare-token loop ends before the completed argument list is returned. Necessary option-loop, command-arm, transaction/TICK and main input/error boundaries preserve subsequent command reachability and reply order. A brace or end on its own is retained when it establishes such a boundary; Python and Quidra retain the corresponding indentation. The quoted-token path, unrelated commands and outer declaration framing remain excluded.

The excerpt contains 2529 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
