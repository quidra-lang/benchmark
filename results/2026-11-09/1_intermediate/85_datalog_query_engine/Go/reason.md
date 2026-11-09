# Task B selection — Go

## Answer requirements shared across languages

1. Trace ordinary nonaggregate query answers from satisfying bindings through variable-column projection, duplicate removal, lexicographic value/tuple comparison, ordered row traversal and existing answer formatting.
2. Explain a descending-row modification that preserves variable-column order, integer-before-symbol value comparison, model construction, aggregate results, proof selection, and the final answer count.

## Selected source locations

- `main.go`: 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785, 818, 819, 820, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 913, 1131, 1132, 1133, 1134, 1135, 1136, 1151, 1170, 1171, 1172, 1173, 1174, 1175, 1176, 1177, 1178, 1179, 1180, 1181, 1182

## Evidence and language semantics

The excerpt supplies the ordered answer representation and its ordinary output consumer. The minimal behavioral change is to traverse those existing deduplicated, ascending rows in reverse only when printing a nonaggregate query with variables. It must not reverse the columns within a tuple or negate the globally shared value comparator: integers retain their existing precedence before symbols, and each row keeps the same name/value formatting. Empty-variable truth answers and the final answer count do not depend on traversal direction. The source makes the aggregate branch boundary visible so the modification stays outside aggregate evaluation. The finished-key map deduplicates complete bindings, answerRows projects names and sorts via compareTuple. Walk answer indexes backward only in the nonaggregate default branch; keep columns and compareValue unchanged.

## Minimization and alternatives

The selected lines begin at already satisfying solver bindings, because the proposed change does not alter joins, filters, fixed-point/model construction, parsing, or safety checks. The projection/deduplication and relevant comparator bodies are retained rather than assuming a custom sort or key is correct from its name. Standard ordered-set/map, derived ordering and sequence semantics are used where the language guarantees them. Reversing only the output iterator is smaller and safer than introducing a second comparator or changing the shared answers routine; proof/constraint callers therefore need no edits. Aggregate bodies and proof construction are omitted because the selected branch guards establish that they are bypassed by the change. This is a Task B explanation, not an implementation.

The excerpt contains 1514 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
