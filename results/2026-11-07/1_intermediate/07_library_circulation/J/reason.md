# Task B selection — J

## Answer requirements shared across languages

1. Trace a valid RETURN of an existing loan with an already waiting reservation: command/date/member/title/loan checks, fine and history/loan closure, queue-head selection, and ordered RETURN/HOLD notices.
2. Locate new-hold construction, its stored owner/expiry and first-open-day calculation; identify the local plus-three to plus-five policy change without implementing it or recomputing previously stored expiries.
3. Follow DAY through the stored-expiry boundary: at expiry the hold remains valid; after expiry charge the correct member fee, remove the old hold, print EXPIRED, and release/reassign the copy using the same new-hold helper.

## Selected source locations

- `main.ijs`: 53, 54, 56, 57, 59, 60, 61, 62, 65, 66, 67, 68, 71, 72, 74, 75, 78, 79, 85, 86, 87, 89, 90, 91, 99, 100, 102, 103, 104, 105, 107, 108, 109, 123, 124, 125, 126, 127, 128, 153, 154, 156, 157, 158, 160, 161, 162, 163, 164, 165, 166, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 183, 184, 185, 186, 187, 188, 189, 190, 192, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 266, 267, 268, 269, 270, 271, 272, 294, 368, 369, 370, 371, 372, 462, 463, 464, 465, 466, 499, 500, 501, 502, 506, 507, 508, 509, 510, 511, 512

## Evidence and language semantics

The boxed patron/title tables and numeric copy table are updated by pset/tset/cset; field 2 is state (1 loan, 2 hold), field 3 is owner, field 5 due, and field 7 stored expiry. Head/tail on the title queue implements FIFO. The rule vector identifies rate, cap, and fee. DAY jumps to the minimum due/expiry event and uses expiry+1; the strict stored-expiry test still governs release. The queue is already populated in the question, so no RESERVE setup is required. The excerpt traces the valid RETURN path through validation, late fine/ledger/history and closure, then RETURN before HOLD. The new hold computes first-open(current day + 3), stores that date, and prints it. The requested local policy replacement is +3 to +5 only at this creation site. An already stored expiry E is not recomputed: DAY E retains the hold, DAY E+1 charges its previous owner, prints EXPIRED, and releases/reassigns it via the same helper. Closed-day adjustment belongs to creation; expiry processing uses the stored date, including an expiry+1 date that itself is closed.

Targeted internal-boundary review: The copy lookup loop ends before the absent-index result. Next-day search, expiry collection, the expiry predicate, expiry processing and the DAY loop have explicit internal end. lines. The DAY/CLOSED command group closes before the independent personal-command dispatch, so RETURN remains reachable when the DAY test is false.

## Minimization and alternatives

Each retained source line supplies command routing or a required validation, identity/mutation rule, fine/history/ledger effect, FIFO selection, first-open calculation, stored boundary, or notice order. Existing reservation/loan setup, borrowing limits, unrelated reporting, payment, renewal, lost-copy handling and the full ISBN checksum parser are unnecessary for this valid existing-loan scenario. Blank lines and outer routine/class delimiters may be omitted when they add no answer evidence. Internal branch and loop boundaries are retained wherever they establish required reachability, iteration extent or notice order. A smaller set containing only the +3 expression would identify the local edit but could not establish closure, notice order, or non-retroactive expiry behavior; including all command handlers would add unrelated tokens. The selected creation and boundary lines together suffice without expanding the task to unrelated policy changes.

The excerpt contains 1816 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
