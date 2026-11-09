# Task B selection — Julia

## Answer requirements shared across languages

1. Identify the defender-escape input board, queried group/point and depth, and change only its inclusive cutoff from depth >= 40 to depth >= 32; cutoff means escape without a chosen move, while the attacker keeps its cutoff at 40.
2. Explain how candidate defense points come from the queried group liberties and adjacent attacker groups in atari, with duplicate removal and the existing ascending point order.
3. Trace tentative defender placement and rejection, the resulting liberty cases (at least three, exactly two with a failed recursive attack at depth + 1, or failure), and the first successful move / no-escape return without changing ordinary placement legality.

## Selected source locations

- `main.jl`: 146, 147, 148, 150, 151, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180

## Evidence and language semantics

The selected routine takes the current position, target and depth, checks the cutoff before generating moves, then obtains the target group. Candidate liberties are extended only with sole liberties of adjacent attacking groups; the seen set avoids processing the same attacking group repeatedly. In candidate order it calls the existing placement operation, skips its failure result, and returns escape for at least three resulting liberties or exactly two when the depth+1 attacker search fails. The first success returns its point; exhaustion returns false with no point. These are calls to the existing group/adjacency/placement operations: their internal flood fill, capture and legality rules need no modification and the answer does not require deriving them. The shared read needs depth >= (defending ? 32 : 40), retaining (defending,0). Set copy/union! supply unique points and sort!(collect(...)) gives ascending order. The last tuple assignment is the return value on exhaustion under Julia function semantics; success returns (true,q). Short-circuit && and || preserve the liberty logic.

## Minimization and alternatives

A cutoff-only excerpt was considered but cannot explain candidate order, tentative moves, liberty cases or the returned point. A complete board-command handler, group flood fill and placement implementation would add unchanged behavior outside this local change. Separate attacker bodies are omitted except their cutoff; shared attacker/defender readers retain the mode-dependent cutoff and any attacker lines inseparable from necessary complete lines. Memo lookup/storage setup and top-level formatting are unnecessary to locate and explain this local policy; selected result assignments still identify the returned decision. Every retained operation carries an input, branch, candidate-order fact or result required above; syntax-only trailing delimiters and unrelated wrapper dispatch were removed where unambiguous.

The excerpt contains 448 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
