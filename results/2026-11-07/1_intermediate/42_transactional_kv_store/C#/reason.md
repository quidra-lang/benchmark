# Task B selection — C#

## Answer requirements shared across languages

1. Trace bare command tokenization, command dispatch and relevant arity/numeric checks in a valid SET-with-TTL, BEGIN, nested BEGIN/COMMIT, SNAPSHOT/RESTORE, TICK, outer ROLLBACK, GET scenario.
2. Explain that an expiry is an absolute deadline derived from the current logical clock, and that expiry at or before the current clock removes the key.
3. Explain current database ownership, independent transaction and named-snapshot copies, and which copy BEGIN, COMMIT, ROLLBACK, SNAPSHOT and RESTORE retain, discard or install.
4. Explain why restoring a database does not restore the logical clock or the named-snapshot registry and why restored expired entries are removed again.
5. Trace the success/GET/TICK output and show that inner commit leaves the outer rollback available while named snapshots survive and can be restored again.

## Selected source locations

- `Program.cs`: 10, 13, 16, 42, 47, 48, 49, 50, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 113, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 143, 144, 219, 220, 221, 222, 223, 224, 225, 227, 228, 256, 260, 261, 262, 268, 269, 270, 271, 272, 273, 274, 275, 277, 278, 279, 281, 283, 284, 287, 289, 290, 291, 295, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 330, 331, 332, 333, 357, 358, 591, 627, 628, 629, 630, 631, 632, 633, 660, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 677, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 694, 695, 696, 705, 706, 707, 708, 709, 710, 712

## Evidence and language semantics

The same bare-token scenario is used across languages: SET k v EX 5; BEGIN; BEGIN; SET keep inner; COMMIT; SNAPSHOT s; RESTORE s; TICK 6; ROLLBACK; GET k; RESTORE s; GET keep; GET k. It distinguishes an outer transaction copy, an inner commit, and a retained named snapshot. The clock starts at zero; the TTL deadline is five; at clock six restoring either saved database removes k. The outer rollback removes keep from the current database but the named snapshot s still supplies it. The immutable TextValue record/string and Entry record make reusing TextValue.Copy() == this safe for this string-only trace; Copy constructs a new Dictionary and new Entry per key. Stack.Push/Pop isolates nested transaction saves, whereas the snapshot dictionary retains its named entry. The selected restoration assignments replace database only; time is a separate integer field, whose default zero initialization is guaranteed by C#. Purge compares each absolute expiry with that unchanged clock. Formatting and main connect OK, removed counts, quoted strings and nil to input commands.

## Minimization and alternatives

Bare arguments avoid the quoted/escaped-token branch. Only the successful command routes needed by the scenario are retained; unrelated data structures and commands are excluded. SET with EX was compared with SET plus EXPIRE: the chosen SET path already shows value creation and its absolute TTL and avoids a second command path. Copy implementations are included only where the language does not itself guarantee independence. Output primitives are retained because their formatting is observable. Restoring only the database field, while time and snapshot/transaction storage are distinct, establishes the unchanged clock and surviving named snapshots without selecting unrelated commands. Each retained declaration, branch, assignment and call supplies a required dependency; necessary internal control boundaries are retained; redundant outer declaration frames and extra context are omitted when they add no fact. The final excerpt was reviewed independently against all common requirements. The bare-token loop ends before the completed argument list is returned. Necessary option-loop, command-arm, transaction/TICK and main input/error boundaries preserve subsequent command reachability and reply order. A brace or end on its own is retained when it establishes such a boundary; Python and Quidra retain the corresponding indentation. The quoted-token path, unrelated commands and outer declaration framing remain excluded.

The excerpt contains 2978 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
