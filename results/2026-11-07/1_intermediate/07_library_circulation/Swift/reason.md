# Task B selection — Swift

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.swift`: 35, 40, 43, 70, 90, 122, 123, 124, 126, 127, 128, 129, 131, 132, 133, 135, 136, 137, 138, 140, 141, 142, 143, 144, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 165, 166, 167, 168, 169, 170, 171, 172, 173, 228, 229, 230, 231, 232, 233, 234, 235, 236, 242, 243, 244, 246, 247, 248, 249, 250, 251, 252, 253, 325, 326, 327, 328, 329, 330, 331, 332

## Evidence and language semantics

Copy reference objects are shared through dictionaries; removeFirst selects FIFO and removeValue closes the old association. Throwing lookup/loan guards stop invalid commands. The RETURN tuple supplies late/fine before release appends HOLD. DAY advances daily and sorts expired copy objects. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: The expired-copy loop and the enclosing calendar-day loop now have explicit independent ends. Swift switch branches already prevent implicit fallthrough.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 1503 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
