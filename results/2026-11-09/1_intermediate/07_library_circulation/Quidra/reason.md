# Task B selection — Quidra

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.qui`: 106, 107, 108, 109, 110, 112, 113, 114, 115, 116, 124, 125, 126, 127, 129, 130, 131, 132, 133, 135, 136, 137, 138, 140, 141, 142, 165, 166, 167, 168, 169, 189, 190, 192, 193, 195, 196, 197, 198, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 213, 214, 215, 216, 217, 218, 221, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 287, 288, 289, 290, 291, 292, 293, 294, 295, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 390, 472, 473, 474, 475, 476, 477, 478, 479, 480, 508, 509, 510, 511, 519, 520, 521, 522, 523, 524, 525

## Evidence and language semantics

The State argument is mutated through explicit references; copy status 1 denotes loan and 2 hold, with member indices. Membership is derived from status/owner, so changing them releases the old association. Queue head index 0 followed by slicing enforces FIFO. Rule vectors are zero-based. DAY jumps to expiry+1 and still checks the stored expiry before charging the old owner. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: No explicit internal delimiter was missing: retained indentation and dedentation already delimit the required guards and loops. The existing selected lines and answer requirements are unchanged.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 2393 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
