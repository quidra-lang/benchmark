# Task B selection — TypeScript

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.ts`: 76, 77, 78, 79, 80, 81, 84, 85, 86, 87, 88, 89, 92, 93, 94, 95, 98, 99, 102, 103, 110, 111, 112, 113, 114, 117, 118, 119, 120, 123, 124, 125, 126, 127, 128, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 145, 146, 147, 148, 149, 150, 151, 152, 189, 190, 191, 192, 193, 194, 195, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 215, 216, 217, 218, 219, 291, 292, 326, 327, 328, 362, 363, 364, 365, 369, 370, 371, 372, 373

## Evidence and language semantics

Typed maps retain shared mutable copy objects; shift consumes FIFO, and delete removes old loan/hold associations. Spread evaluation places RETURN before release notices. DAY increments one day at a time and reads each copy’s stored expiry. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: Unknown-member/title and missing-loan guards end before successful lookup/use; closed-day iteration ends before returning the date. Zero-charge and empty-queue returns end before ledger/FIFO work. Expiry/day loops finish before output is returned, and the DAY dispatch guard closes before circulation dispatch.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 1803 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
