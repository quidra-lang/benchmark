# Task B selection — PHP

## Answer requirements shared across languages

1. Identify the defender-escape input board, queried group/point and depth, and change only its inclusive cutoff from depth >= 40 to depth >= 32; cutoff means escape without a chosen move, while the attacker keeps its cutoff at 40.
2. Explain how candidate defense points come from the queried group liberties and adjacent attacker groups in atari, with duplicate removal and the existing ascending point order.
3. Trace tentative defender placement and rejection, the resulting liberty cases (at least three, exactly two with a failed recursive attack at depth + 1, or failure), and the first successful move / no-escape return without changing ordinary placement legality.

## Selected source locations

- `main.php`: 70, 71, 72, 73, 74, 224, 226, 227, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275

## Evidence and language semantics

The selected routine takes the current position, target and depth, checks the cutoff before generating moves, then obtains the target group. Candidate liberties are extended only with sole liberties of adjacent attacking groups; the seen set avoids processing the same attacking group repeatedly. In candidate order it calls the existing placement operation, skips its failure result, and returns escape for at least three resulting liberties or exactly two when the depth+1 attacker search fails. The first success returns its point; exhaustion returns false with no point. These are calls to the existing group/adjacency/placement operations: their internal flood fill, capture and legality rules need no modification and the answer does not require deriving them. The shared closure captures the target, size, colors and itself; its cutoff must distinguish defending 32 from attacking 40 and return the same [$defending,-1]. PHP arrays here are sets keyed by points; + retains unique keys and the selected ordered helper extracts keys then sorts numerically. The exact reason check filters placement, short-circuit operators preserve liberty cases, and return arrays give true/q or false/-1.

## Minimization and alternatives

A cutoff-only excerpt was considered but cannot explain candidate order, tentative moves, liberty cases or the returned point. A complete board-command handler, group flood fill and placement implementation would add unchanged behavior outside this local change. Separate attacker bodies are omitted except their cutoff; shared attacker/defender readers retain the mode-dependent cutoff and any attacker lines inseparable from necessary complete lines. Memo lookup/storage setup and top-level formatting are unnecessary to locate and explain this local policy; selected result assignments still identify the returned decision. Every retained operation carries an input, branch, candidate-order fact or result required above; syntax-only trailing delimiters and unrelated wrapper dispatch were removed where unambiguous.

The excerpt contains 791 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
