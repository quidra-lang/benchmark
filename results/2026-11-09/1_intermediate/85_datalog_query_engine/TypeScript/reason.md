# Task B selection — TypeScript

## Answer requirements shared across languages

1. Trace ordinary nonaggregate query answers from satisfying bindings through variable-column projection, duplicate removal, lexicographic value/tuple comparison, ordered row traversal and existing answer formatting.
2. Explain a descending-row modification that preserves variable-column order, integer-before-symbol value comparison, model construction, aggregate results, proof selection, and the final answer count.

## Selected source locations

- `main.ts`: 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 413, 451, 452, 453, 454, 455, 468, 469, 470, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 709, 717, 718, 719, 729, 739, 740, 741, 742, 743

## Evidence and language semantics

The excerpt supplies the ordered answer representation and its ordinary output consumer. The minimal behavioral change is to traverse those existing deduplicated, ascending rows in reverse only when printing a nonaggregate query with variables. It must not reverse the columns within a tuple or negate the globally shared value comparator: integers retain their existing precedence before symbols, and each row keeps the same name/value formatting. Empty-variable truth answers and the final answer count do not depend on traversal direction. The source makes the aggregate branch boundary visible so the modification stays outside aggregate evaluation. Canonical bindingKey distinguishes bigint and symbol encodings, the Map removes repeated bindings, and rows.sort(tupleCompare) orders projected rows. Reverse only the ordinary query row mapping, preserving shared arrays and proofs.

## Minimization and alternatives

The selected lines begin at already satisfying solver bindings, because the proposed change does not alter joins, filters, fixed-point/model construction, parsing, or safety checks. The projection/deduplication and relevant comparator bodies are retained rather than assuming a custom sort or key is correct from its name. Standard ordered-set/map, derived ordering and sequence semantics are used where the language guarantees them. Reversing only the output iterator is smaller and safer than introducing a second comparator or changing the shared answers routine; proof/constraint callers therefore need no edits. Aggregate bodies and proof construction are omitted because the selected branch guards establish that they are bypassed by the change. This is a Task B explanation, not an implementation.

The excerpt contains 1253 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
