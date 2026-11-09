# Task B selection — C

## Answer requirements shared across languages

1. Identify the defender-escape input board, queried group/point and depth, and change only its inclusive cutoff from depth >= 40 to depth >= 32; cutoff means escape without a chosen move, while the attacker keeps its cutoff at 40.
2. Explain how candidate defense points come from the queried group liberties and adjacent attacker groups in atari, with duplicate removal and the existing ascending point order.
3. Trace tentative defender placement and rejection, the resulting liberty cases (at least three, exactly two with a failed recursive attack at depth + 1, or failure), and the first successful move / no-escape return without changing ordinary placement legality.

## Selected source locations

- `main.c`: 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 502, 503

## Evidence and language semantics

The selected routine takes the current position, target and depth, checks the cutoff before generating moves, then obtains the target group. Candidate liberties are extended only with sole liberties of adjacent attacking groups; the seen set avoids processing the same attacking group repeatedly. In candidate order it calls the existing placement operation, skips its failure result, and returns escape for at least three resulting liberties or exactly two when the depth+1 attacker search fails. The first success returns its point; exhaustion returns false with no point. These are calls to the existing group/adjacency/placement operations: their internal flood fill, capture and legality rules need no modification and the answer does not require deriving them. The separate defend_ladder returns integer 1 for escape and 0 for failure; first is written only on success. Change line 466 alone. attack_ladder line 503 stays at 40. Candidate bitmap indices are scanned from 0 upwards, so duplicates occupy one bit and the first winning index wins. C short-circuit || and && avoid the recursive attack except in the exactly-two case.

## Minimization and alternatives

A cutoff-only excerpt was considered but cannot explain candidate order, tentative moves, liberty cases or the returned point. A complete board-command handler, group flood fill and placement implementation would add unchanged behavior outside this local change. Separate attacker bodies are omitted except their cutoff; shared attacker/defender readers retain the mode-dependent cutoff and any attacker lines inseparable from necessary complete lines. Memo lookup/storage setup and top-level formatting are unnecessary to locate and explain this local policy; selected result assignments still identify the returned decision. Every retained operation carries an input, branch, candidate-order fact or result required above; syntax-only trailing delimiters and unrelated wrapper dispatch were removed where unambiguous.

The excerpt contains 721 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
