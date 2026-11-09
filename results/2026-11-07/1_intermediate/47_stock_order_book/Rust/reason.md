# Task B selection — Rust

## Answer requirements shared across languages

1. Identify the eligible best opposite-side resting order by price and time priority, and repeat that choice after each match or cancellation.
2. Trace consumption of the visible slice and remaining quantity, then replenishment to min(peak, remaining) with new time priority when hidden quantity remains.
3. Establish TRADE-before-REFRESH output order and explain that the next eligible best order can be another order at the same price.
4. For a best resting order owned by the incoming trader, identify the resting-order cancellation, retained incoming quantity, and the control flow that skips trade, fees, and refresh.

## Selected source locations

- `main.rs`: 13, 14, 15, 16, 17, 18, 46, 47, 48, 49, 50, 51, 74, 75, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 230, 231, 232, 233, 234, 235, 236, 239, 240, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 257, 258, 259, 260

## Evidence and language semantics

The match loop reselects the best opposite-side order each iteration. The ordering key prioritizes the best price and then the oldest priority. A fill consumes the smaller of the incoming remainder and the maker visible slice; the retained maker remainder is the hidden-plus-visible quantity. Exhausting a slice with a positive remainder assigns a fresh priority and exposes min(peak, remainder), placing it behind older resting orders at the same price. The trade output is produced before that refresh output. The same-trader guard cancels the resting maker and continues before fill, fee, and refresh processing, so the incoming remainder is not consumed. Rust uses stored indices for book ordering and &mut references for actual order mutation; no local value copy is mistaken for a committed mutation. sort_by_key chooses a tuple, first/copy returns the best index, fill subtracts remaining, and Vec::push retains output order. retain removes the cancelled resting index. continue bypasses trade creation, fee mutations and refresh.

## Minimization and alternatives

Reviewed the excerpt independently against the four shared requirements. The alternative of including the entire matching routine, all order/trader declarations, post-order placement, and command dispatch adds unrelated accounting, history, risk checks, and order types. Selected only the comparison/selection contract, control-flow boundaries, quantity and priority changes, relevant fee position, and output-producing lines; field access and standard collection/minimum/control-flow semantics supply the rest. Book/history reporting and initial iceberg acceptance are unnecessary because the question begins with an existing resting iceberg order. Custom selection, fill, and output helpers are followed only where their semantics are necessary; unused helper bodies and routine closing punctuation with no additional scope information are omitted.

The excerpt contains 1423 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
