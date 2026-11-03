# Task B selection: 78_bank_account / Python

## Common answer requirements

Trace the two Emma-to-Nina transfers, equality and atomic failure, then the immediately following Emma withdrawal.

## Source evidence and minimization

Emma starts at 800 and receives 1200, reaching 2000. Nina starts at 12000 and transfers 5000 to Leo, reaching 7000. The 2500 transfer fails without either guarded mutation; equality allows the 2000 transfer, leaving Emma 0 and Nina 9000. The subsequent 300 withdrawal fails. Both Leo-only withdrawals are omitted: independent dictionary entries and the selected guarded operations show they cannot change Emma or Nina. The same relevance boundary is used for Quidra. Relevant transaction records, parsing, the >= test and both guarded transfer updates remain.

Selected original source lines: L1, L2, L3, L5, L7, L8, L9, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24.
Every selected line is complete, verbatim and in source order. Alternative complete
source and contiguous-context selections retain unrelated information; the removed
input records or independent operations add no required fact. This is a reviewed
sufficient minimized candidate, not a proof of a global mathematical minimum.
Language and documented library semantics are available as prior knowledge.

Task B: 276 tokens under the unchanged metric/tokenizer.py. Task A is unchanged
by this evidence correction.
