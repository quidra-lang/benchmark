# Task B selection — Dart

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `main.dart`: 8, 12, 13, 14, 15, 16, 17, 18, 65, 66, 67, 68, 69, 72, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 116, 117, 118, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 155, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 284, 288, 289, 290, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 315, 316, 317, 318, 319, 320, 321, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 356, 357, 358, 359, 384, 385, 594, 627, 628, 629, 630, 631, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 695, 696, 697, 701, 702, 703, 704, 705, 706, 707

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. Map is reference-bearing in Dart, so Store.copy and Entry.copy are selected to establish new maps and records. TextValue has a final String payload and copy returns this safely for this trace; const alone is not used as a blanket guarantee about arbitrary nested data. transactions.removeLast consumes only one saved map. Named restore copies its saved map and does not delete it. The separate time field remains advanced after database restoration; purge explicitly removes expiry <= time. All observed values flow from the relevant parser and command registration to stdout formatting.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; standalone closing delimiters and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements.

The excerpt contains 2849 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
