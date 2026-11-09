# Task B selection — Zig

## Answer requirements shared across languages

1. Trace ordinary nonaggregate query answers from satisfying bindings through variable-column projection, duplicate removal, lexicographic value/tuple comparison, ordered row traversal and existing answer formatting.
2. Explain a descending-row modification that preserves variable-column order, integer-before-symbol value comparison, model construction, aggregate results, proof selection, and the final answer count.

## Selected source locations

- `main.zig`: 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 520, 521, 522, 523, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 575, 576, 577, 578, 579, 580, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 850, 851, 852, 853, 854, 855, 867, 883, 884, 885, 886, 887

## Evidence and language semantics

The excerpt supplies the ordered answer representation and its ordinary output consumer. The minimal behavioral change is to traverse those existing deduplicated, ascending rows in reverse only when printing a nonaggregate query with variables. It must not reverse the columns within a tuple or negate the globally shared value comparator: integers retain their existing precedence before symbols, and each row keeps the same name/value formatting. Empty-variable truth answers and the final answer count do not depend on traversal direction. The source makes the aggregate branch boundary visible so the modification stays outside aggregate evaluation. SolutionSearch.finished removes duplicate canonical assignment keys; answerRows projects names and std.mem.sort uses ascending compareTuple. Change only ordinary-query traversal to descending indices, keeping unsigned-loop termination safe and all comparison semantics unchanged.

## Minimization and alternatives

The selected lines begin at already satisfying solver bindings, because the proposed change does not alter joins, filters, fixed-point/model construction, parsing, or safety checks. The projection/deduplication and relevant comparator bodies are retained rather than assuming a custom sort or key is correct from its name. Standard ordered-set/map, derived ordering and sequence semantics are used where the language guarantees them. Reversing only the output iterator is smaller and safer than introducing a second comparator or changing the shared answers routine; proof/constraint callers therefore need no edits. Aggregate bodies and proof construction are omitted because the selected branch guards establish that they are bypassed by the change. This is a Task B explanation, not an implementation.

The excerpt contains 2157 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
