# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.rb`: 49, 50, 53, 54, 57, 58, 59, 62, 63, 70, 71, 78, 79, 80, 83, 84, 85, 86, 89, 90, 91, 92, 94, 97, 98, 99, 100, 101, 103, 104, 105, 106, 107, 108, 111, 112, 113, 114, 115, 116, 117, 150, 151, 152, 153, 154, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 170, 173, 174, 175, 233, 259, 260, 261, 282, 283, 285, 286, 287, 288, 289

## Evidence and language semantics

Hashes hold shared mutable copy objects. Array#shift consumes FIFO; Hash#delete removes old associations, while release changes the existing copy. The notice array concatenates RETURN before release output. DAY visits integer dates in order. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Standalone empty/closing lines are omitted because the excerpt is evidence, not a compilable replacement. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 1255 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
