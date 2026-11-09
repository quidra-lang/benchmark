# Task B selection — Zig

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.zig`: 100, 101, 102, 103, 104, 150, 151, 152, 153, 154, 155, 186, 187, 190, 191, 228, 229, 230, 231, 232, 235, 236, 239, 240, 243, 244, 245, 246, 247, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 263, 264, 265, 266, 267, 268, 269, 270, 271, 308, 309, 310, 311, 312, 313, 314, 315, 318, 319, 320, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 400, 401, 402, 403, 435, 436, 437, 438, 439, 440, 441, 442, 443

## Evidence and language semantics

Pointers to member/title/copy objects retain shared state. titleCopy derives loan/hold membership from state and owner; setting AVAILABLE/null removes the old association. orderedRemove(0) preserves FIFO. try propagates lookup/charge errors. DAY advances daily; release stores a new expiry only after selecting a waiting member. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: The copy-search loop ends before return null; the empty-queue return ends before orderedRemove. Nested expiry collection ends before charging/release, then the expiry loop and DAY while close independently.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 2109 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
