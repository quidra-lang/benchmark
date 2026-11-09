# Task B selection — Python

## Answer requirements shared across languages

1. Follow PARSE formula validation to the resulting element composition and charge, and distinguish the summary from the per-element list.
2. Explain existing Hill ordering and count formatting; identify the list traversal and final output construction.
3. Reverse only the PARSE per-element traversal, retaining the original Hill summary, composition values, shared ordering helpers and all other commands.

## Selected source locations

- `main.py`: 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 474, 475, 476, 477, 478, 479, 480

## Evidence and language semantics

The selected PARSE path passes the formula argument through the existing parser/validation boundary, obtains its composition and charge, computes Hill order, and builds a single result containing a Hill summary plus element/count pairs and signed charge. The parser excerpt shows construction of the composition, hydrate combination, signed charge and final syntax/unknown-element checks; recursive sequence parsing remains unaffected. Hill ordering places C first and H second when carbon occurs, then sorts the other symbols; without carbon it sorts all symbols. Count one is omitted from the Hill summary, whereas the explicit list prints every count. To meet the proposal, traverse a reversed copy/view of the PARSE-local ordered element list only when creating the comma-separated pairs. Keep the call to Hill/hill_notation on the original composition and charge and leave the shared order helper unchanged. In C++/Rust ordered map iteration supplies initial lexical symbol order; other implementations sort explicitly. The element-index table is selected where C/H are represented by numeric indices. Standard reverse iteration/copy semantics suffice; do not mutate the composition. 

## Minimization and alternatives

The command branch, top-level validation/construction result, Hill order and formatter are distinct dependencies. Recursive group parsing, element weights, mass calculations and equation solving do not affect the proposed output-list traversal and are omitted. Keeping the parser boundary is sufficient to identify preserved validation; no change to its recursive helpers is proposed. Reversing the shared ordering helper or the composition would also reverse the summary and other commands, so that alternative is rejected. Reversing only the already-created pair sequence is an equivalent small alternative when available; reversing its local element traversal avoids touching shared state. Unrelated mass variables are omitted unless they share a complete selected line.

The excerpt contains 737 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
