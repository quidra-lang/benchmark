# Task B selection — Rust

## Answer requirements shared across languages

1. Identify command-time initialization and the unconditional automatic waiting-queue expiry before dispatching a successful QUOTE.
2. Explain inclusive thirty-minute expiry, head-to-tail removal, the deadline printed for GIVEUP, and its output preceding QUOTE.
3. Determine whether expiry or QUOTE changes parked vehicles, payment records, or the waiting queue, tracing fee/output dependencies to distinguish reading state from writing it.
4. Explain why QUOTE neither admits waiting vehicles nor records a payment; identify the control flow separating those operations.

## Selected source locations

- `main.rs`: 31, 32, 33, 34, 84, 85, 86, 87, 146, 147, 148, 149, 150, 151, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 262, 285, 441, 442, 443, 444, 480, 481, 482, 905, 906, 907, 908, 909, 910, 913, 914, 915, 916, 918

## Evidence and language semantics

The command loop sets elapsed minute time, expires waiters before dispatch, and preserves output order. The expiry loop scans the queue in its stored order, removes every entry whose wait is at least 30, retains younger entries, and prints the joined-time-plus-30 deadline. Its other writes are refusal statistics, not parked-vehicle or payment changes. On a successful QUOTE the selected branch only looks up a parked vehicle, calculates charges without loss, and emits the fee line. The fee helpers read payment/vehicle/rate/pass fields and build local amounts; they never assign a vehicle/payment/queue field. Output helpers only format or append/write output. Hence the queue can shrink before QUOTE, while parked data and payments survive; QUOTE itself changes neither. Its selected branch has no admission or payment write. The relevant garage fields are ordinary Vec/BTreeMap and payment fields are ordinary bool/i32. Shared &self and &Vehicle borrows on bill and fee_line do not permit mutation of those fields; their implementations are therefore unnecessary for this state-effect question. mem::take transfers the old Vec, and iteration/push preserve waiter order. Only output is mutably borrowed in the QUOTE arm.

## Minimization and alternatives

Independent excerpt-only review checked all four requirements: pre-dispatch expiry is distinct from the selected command, >=/<= includes the exact thirty-minute boundary, output order follows the visible calls/appends, and all reachable fee operations preserve vehicle/payment/queue state. Considered retaining the full command dispatcher, PAY/EXIT implementations and queue-admission algorithm; these cost more tokens and are unreachable for a successful QUOTE. Their branch boundaries or the common admission predicate suffice. Considered selecting only the QUOTE call: that is cheaper but loses expiry ordering and, without a language-enforced read-only contract, cannot establish helper side effects. Unrelated fee defaults, parking assignment, reports, and errors are excluded; complete original lines are kept in source order.

The excerpt contains 881 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
