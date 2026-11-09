# Task B selection — Ruby

## Answer requirements shared across languages

1. Identify command-time initialization and the unconditional automatic waiting-queue expiry before dispatching a successful QUOTE.
2. Explain inclusive thirty-minute expiry, head-to-tail removal, the deadline printed for GIVEUP, and its output preceding QUOTE.
3. Determine whether expiry or QUOTE changes parked vehicles, payment records, or the waiting queue, tracing fee/output dependencies to distinguish reading state from writing it.
4. Explain why QUOTE neither admits waiting vehicles nor records a payment; identify the control flow separating those operations.

## Selected source locations

- `main.rb`: 16, 17, 18, 27, 28, 29, 30, 31, 32, 33, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 75, 76, 77, 78, 79, 80, 81, 82, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 231, 232, 233, 325, 326, 327, 328, 496, 497, 498, 499, 500, 501, 502, 511

## Evidence and language semantics

The command loop sets elapsed minute time, expires waiters before dispatch, and preserves output order. The expiry loop scans the queue in its stored order, removes every entry whose wait is at least 30, retains younger entries, and prints the joined-time-plus-30 deadline. Its other writes are refusal statistics, not parked-vehicle or payment changes. On a successful QUOTE the selected branch only looks up a parked vehicle, calculates charges without loss, and emits the fee line. The fee helpers read payment/vehicle/rate/pass fields and build local amounts; they never assign a vehicle/payment/queue field. Output helpers only format or append/write output. Hence the queue can shrink before QUOTE, while parked data and payments survive; QUOTE itself changes neither. Its selected branch has no admission or payment write. Ruby object references and method names do not establish purity, so the called helper bodies are included. Arithmetic/string operations and Array/Hash reads do not change vehicle fields; local amounts are returned. The next when branch terminates QUOTE and the outer execute has no common queue admission.

## Minimization and alternatives

Independent excerpt-only review checked all four requirements: pre-dispatch expiry is distinct from the selected command, >=/<= includes the exact thirty-minute boundary, output order follows the visible calls/appends, and all reachable fee operations preserve vehicle/payment/queue state. Considered retaining the full command dispatcher, PAY/EXIT implementations and queue-admission algorithm; these cost more tokens and are unreachable for a successful QUOTE. Their branch boundaries or the common admission predicate suffice. Considered selecting only the QUOTE call: that is cheaper but loses expiry ordering and, without a language-enforced read-only contract, cannot establish helper side effects. Unrelated fee defaults, parking assignment, reports, and errors are excluded; complete original lines are kept in source order.

The excerpt contains 1373 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
