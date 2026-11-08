# Task B selection — Zig

## Answer requirements shared across languages

1. Identify the defender-escape input board, queried group/point and depth, and change only its inclusive cutoff from depth >= 40 to depth >= 32; cutoff means escape without a chosen move, while the attacker keeps its cutoff at 40.
2. Explain how candidate defense points come from the queried group liberties and adjacent attacker groups in atari, with duplicate removal and the existing ascending point order.
3. Trace tentative defender placement and rejection, the resulting liberty cases (at least three, exactly two with a failed recursive attack at depth + 1, or failure), and the first successful move / no-escape return without changing ordinary placement legality.

## Selected source locations

- `main.zig`: 335, 336, 337, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 377, 378, 379, 380

## Evidence and language semantics

The selected routine takes the current position, target and depth, checks the cutoff before generating moves, then obtains the target group. Candidate liberties are extended only with sole liberties of adjacent attacking groups; the seen set avoids processing the same attacking group repeatedly. In candidate order it calls the existing placement operation, skips its failure result, and returns escape for at least three resulting liberties or exactly two when the depth+1 attacker search fails. The first success returns its point; exhaustion returns false with no point. These are calls to the existing group/adjacency/placement operations: their internal flood fill, capture and legality rules need no modification and the answer does not require deriving them. ladderRead is shared: the cutoff must distinguish defending >=32 and attacking >=40, retaining success=defending. Reading defaults move to null. Fixed-size candidate and seen bitmaps deduplicate; the 0..n*n traversal supplies increasing point order without a sort helper. The ordinary placement reason remains untouched, then the defender >=3/exactly-two branches use the recursive attacker flag. First good returns success=true,move=p, and exhaustion success=false with null move.

## Minimization and alternatives

A cutoff-only excerpt was considered but cannot explain candidate order, tentative moves, liberty cases or the returned point. A complete board-command handler, group flood fill and placement implementation would add unchanged behavior outside this local change. Separate attacker bodies are omitted except their cutoff; shared attacker/defender readers retain the mode-dependent cutoff and any attacker lines inseparable from necessary complete lines. Memo lookup/storage setup and top-level formatting are unnecessary to locate and explain this local policy; selected result assignments still identify the returned decision. Every retained operation carries an input, branch, candidate-order fact or result required above; syntax-only trailing delimiters and unrelated wrapper dispatch were removed where unambiguous.

The excerpt contains 737 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
