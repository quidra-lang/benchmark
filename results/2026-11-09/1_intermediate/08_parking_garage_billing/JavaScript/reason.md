# Task B selection — JavaScript

## Answer requirements shared across languages

1. Identify command-time initialization and the unconditional automatic waiting-queue expiry before dispatching a successful QUOTE.
2. Explain inclusive thirty-minute expiry, head-to-tail removal, the deadline printed for GIVEUP, and its output preceding QUOTE.
3. Determine whether expiry or QUOTE changes parked vehicles, payment records, or the waiting queue, tracing fee/output dependencies to distinguish reading state from writing it.
4. Explain why QUOTE neither admits waiting vehicles nor records a payment; identify the control flow separating those operations.

## Selected source locations

- `main.js`: 13, 14, 15, 20, 41, 42, 43, 44, 45, 46, 47, 48, 49, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 199, 200, 201, 305, 306, 307, 308, 309, 504, 505, 506, 507, 508, 509, 510, 521

## Evidence and language semantics

The command loop sets elapsed minute time, expires waiters before dispatch, and preserves output order. The expiry loop scans the queue in its stored order, removes every entry whose wait is at least 30, retains younger entries, and prints the joined-time-plus-30 deadline. Its other writes are refusal statistics, not parked-vehicle or payment changes. On a successful QUOTE the selected branch only looks up a parked vehicle, calculates charges without loss, and emits the fee line. The fee helpers read payment/vehicle/rate/pass fields and build local amounts; they never assign a vehicle/payment/queue field. Output helpers only format or append/write output. Hence the queue can shrink before QUOTE, while parked data and payments survive; QUOTE itself changes neither. Its selected branch has no admission or payment write. JavaScript const does not make objects immutable, so the calculation, lookup and formatting bodies are retained rather than treating const bindings as a purity guarantee. Array iteration and push preserve order; Map.has/get and the shown output append do not mutate vehicle/payment/queue objects.

## Minimization and alternatives

Independent excerpt-only review checked all four requirements: pre-dispatch expiry is distinct from the selected command, >=/<= includes the exact thirty-minute boundary, output order follows the visible calls/appends, and all reachable fee operations preserve vehicle/payment/queue state. Considered retaining the full command dispatcher, PAY/EXIT implementations and queue-admission algorithm; these cost more tokens and are unreachable for a successful QUOTE. Their branch boundaries or the common admission predicate suffice. Considered selecting only the QUOTE call: that is cheaper but loses expiry ordering and, without a language-enforced read-only contract, cannot establish helper side effects. Unrelated fee defaults, parking assignment, reports, and errors are excluded; complete original lines are kept in source order.

The excerpt contains 1565 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
