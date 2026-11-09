# Task B selection — Quidra

## Answer requirements shared across languages

1. Trace ordinary nonaggregate query answers from satisfying bindings through variable-column projection, duplicate removal, lexicographic value/tuple comparison, ordered row traversal and existing answer formatting.
2. Explain a descending-row modification that preserves variable-column order, integer-before-symbol value comparison, model construction, aggregate results, proof selection, and the final answer count.

## Selected source locations

- `main.qui`: 4, 5, 6, 7, 8, 9, 10, 11, 12, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 437, 438, 439, 440, 441, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816

## Evidence and language semantics

The excerpt supplies the ordered answer representation and its ordinary output consumer. The minimal behavioral change is to traverse those existing deduplicated, ascending rows in reverse only when printing a nonaggregate query with variables. It must not reverse the columns within a tuple or negate the globally shared value comparator: integers retain their existing precedence before symbols, and each row keeps the same name/value formatting. Empty-variable truth answers and the final answer count do not depend on traversal direction. The source makes the aggregate branch boundary visible so the modification stays outside aggregate evaluation. Predicate membership uses Row.encoded and typed Datum encodings; sorted_rows is an ascending merge under row_before/Datum.before. Reverse only the rows traversed by the empty-aggregate output comprehension.

## Minimization and alternatives

The selected lines begin at already satisfying solver bindings, because the proposed change does not alter joins, filters, fixed-point/model construction, parsing, or safety checks. The projection/deduplication and relevant comparator bodies are retained rather than assuming a custom sort or key is correct from its name. Standard ordered-set/map, derived ordering and sequence semantics are used where the language guarantees them. Reversing only the output iterator is smaller and safer than introducing a second comparator or changing the shared answers routine; proof/constraint callers therefore need no edits. Aggregate bodies and proof construction are omitted because the selected branch guards establish that they are bypassed by the change. This is a Task B explanation, not an implementation.

The excerpt contains 1654 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
