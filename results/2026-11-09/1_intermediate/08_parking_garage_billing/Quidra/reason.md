# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify command-time initialization and the unconditional automatic waiting-queue expiry before dispatching a successful QUOTE.
2. Explain inclusive thirty-minute expiry, head-to-tail removal, the deadline printed for GIVEUP, and its output preceding QUOTE.
3. Determine whether expiry or QUOTE changes parked vehicles, payment records, or the waiting queue, tracing fee/output dependencies to distinguish reading state from writing it.
4. Explain why QUOTE neither admits waiting vehicles nor records a payment; identify the control flow separating those operations.

## Selected source locations

- `main.qui`: 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 188, 203, 221, 222, 223, 260, 261, 262, 263, 264, 265, 369, 370, 371, 372, 373, 374, 375, 376, 393, 394, 409, 410, 419, 420, 421, 422, 423, 424, 425, 430, 431, 432, 450, 451

## Evidence and language semantics

The command loop sets elapsed minute time, expires waiters before dispatch, and preserves output order. The expiry loop scans the queue in its stored order, removes every entry whose wait is at least 30, retains younger entries, and prints the joined-time-plus-30 deadline. Its other writes are refusal statistics, not parked-vehicle or payment changes. On a successful QUOTE the selected branch only looks up a parked vehicle, calculates charges without loss, and emits the fee line. The fee helpers read payment/vehicle/rate/pass fields and build local amounts; they never assign a vehicle/payment/queue field. Output helpers only format or append/write output. Hence the queue can shrink before QUOTE, while parked data and payments survive; QUOTE itself changes neither. Its selected branch has no admission or payment write. The const State parameters on exit_fees and fee_line prohibit mutation through those values; neither call has &state mutation authority. Their implementations are unnecessary to establish preservation of vehicle/payment/queue state. The shared branch tests PAY and EXIT before their writes; QUOTE takes the fee_line path and returns. Collection traversal and append retain waiter order.

## Minimization and alternatives

Independent excerpt-only review checked all four requirements: pre-dispatch expiry is distinct from the selected command, >=/<= includes the exact thirty-minute boundary, output order follows the visible calls/appends, and all reachable fee operations preserve vehicle/payment/queue state. Considered retaining the full command dispatcher, PAY/EXIT implementations and queue-admission algorithm; these cost more tokens and are unreachable for a successful QUOTE. Their branch boundaries or the common admission predicate suffice. Considered selecting only the QUOTE call: that is cheaper but loses expiry ordering and, without a language-enforced read-only contract, cannot establish helper side effects. Unrelated fee defaults, parking assignment, reports, and errors are excluded; complete original lines are kept in source order.

The excerpt contains 959 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
