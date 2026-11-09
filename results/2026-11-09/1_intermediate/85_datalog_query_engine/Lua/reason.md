# Task B selection — Lua

## Answer requirements shared across languages

1. Trace ordinary nonaggregate query answers from satisfying bindings through variable-column projection, duplicate removal, lexicographic value/tuple comparison, ordered row traversal and existing answer formatting.
2. Explain a descending-row modification that preserves variable-column order, integer-before-symbol value comparison, model construction, aggregate results, proof selection, and the final answer count.

## Selected source locations

- `main.lua`: 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 603, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 688, 689, 690, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 983, 984, 985, 986, 987, 1002, 1024, 1025, 1026, 1027, 1028, 1029, 1030

## Evidence and language semantics

The excerpt supplies the ordered answer representation and its ordinary output consumer. The minimal behavioral change is to traverse those existing deduplicated, ascending rows in reverse only when printing a nonaggregate query with variables. It must not reverse the columns within a tuple or negate the globally shared value comparator: integers retain their existing precedence before symbols, and each row keeps the same name/value formatting. Empty-variable truth answers and the final answer count do not depend on traversal direction. The source makes the aggregate branch boundary visible so the modification stays outside aggregate evaluation. The finished set uses an ordered binding tuple_key, then answer_rows explicitly sorts projected rows. A backward numeric loop over answers only at the ordinary query output preserves all other consumers.

## Minimization and alternatives

The selected lines begin at already satisfying solver bindings, because the proposed change does not alter joins, filters, fixed-point/model construction, parsing, or safety checks. The projection/deduplication and relevant comparator bodies are retained rather than assuming a custom sort or key is correct from its name. Standard ordered-set/map, derived ordering and sequence semantics are used where the language guarantees them. Reversing only the output iterator is smaller and safer than introducing a second comparator or changing the shared answers routine; proof/constraint callers therefore need no edits. Aggregate bodies and proof construction are omitted because the selected branch guards establish that they are bypassed by the change. This is a Task B explanation, not an implementation.

The excerpt contains 1300 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
