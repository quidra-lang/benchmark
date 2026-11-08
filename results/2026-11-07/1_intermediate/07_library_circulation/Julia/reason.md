# Task B selection — Julia

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.jl`: 64, 65, 66, 68, 69, 70, 71, 73, 76, 77, 78, 79, 80, 82, 83, 84, 85, 87, 88, 89, 90, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 104, 105, 106, 107, 108, 109, 110, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 234, 235, 236, 237, 238, 264, 265, 266, 267, 268, 269, 270

## Evidence and language semantics

Mutable copy objects are shared through dictionaries; popfirst! consumes the FIFO queue, delete! removes the old member association, and release stores a new expiry. Rules use Julia one-based tuple positions. DAY skips to the next due/expiry event, explicitly expiry+1, then tests stored expiry strictly below CURRENT_DAY. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: Closed-day iteration and empty-queue guards finish before their successful results. Loan/hold/member next-boundary searches finish before the beyond-target check, which ends before assigning CURRENT_DAY. Expiry collection finishes before release mutations, and the expiry/day loops end separately.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 1385 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
