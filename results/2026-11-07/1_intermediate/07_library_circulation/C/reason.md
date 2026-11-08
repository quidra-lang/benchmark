# Task B selection — C

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.c`: 131, 132, 133, 135, 136, 137, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 151, 152, 153, 155, 157, 158, 159, 160, 162, 163, 164, 166, 167, 168, 169, 170, 171, 175, 176, 177, 183, 184, 185, 186, 187, 189, 190, 191, 196, 197, 198, 200, 205, 207, 208, 209, 210, 211, 213, 214, 215, 216, 217, 218, 219, 231, 232, 233, 234, 235, 236, 237, 238, 239, 244, 245, 246, 247, 248, 249, 294, 295, 296, 297, 298, 299, 300, 301, 309, 310, 311, 312, 313, 314, 315, 318, 319, 320, 321, 322, 323, 324, 325, 405, 406, 407, 408, 409, 410, 411, 412, 439, 440, 441, 442, 447

## Evidence and language semantics

References are title/copy indices into shared arrays; `state` maintains state counts, `remove_ref` removes the old member association, and `remove_queue` shifts FIFO entries. `loss` is false for RETURN; the selected else branches therefore record a returned loan and release the same indexed copy. DAY visits consecutive dates. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Standalone empty/closing lines are omitted because the excerpt is evidence, not a compilable replacement. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 2492 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
