# Task B selection — C++

## Answer requirements shared across languages

1. Identify the eligible best opposite-side resting order by price and time priority, and repeat that choice after each match or cancellation.
2. Trace consumption of the visible slice and remaining quantity, then replenishment to min(peak, remaining) with new time priority when hidden quantity remains.
3. Establish TRADE-before-REFRESH output order and explain that the next eligible best order can be another order at the same price.
4. For a best resting order owned by the incoming trader, identify the resting-order cancellation, retained incoming quantity, and the control flow that skips trade, fees, and refresh.

## Selected source locations

- `main.cpp`: 28, 29, 34, 35, 81, 82, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 141, 142, 143, 144, 145, 146, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 176, 177, 178, 179, 182, 185, 186, 187, 188, 189, 190, 191, 193, 194, 195

## Evidence and language semantics

The match loop reselects the best opposite-side order each iteration. The ordering key prioritizes the best price and then the oldest priority. A fill consumes the smaller of the incoming remainder and the maker visible slice; the retained maker remainder is the hidden-plus-visible quantity. Exhausting a slice with a positive remainder assigns a fresh priority and exposes min(peak, remainder), placing it behind older resting orders at the same price. The trade output is produced before that refresh output. The same-trader guard cancels the resting maker and continues before fill, fee, and refresh processing, so the incoming remainder is not consumed. C++ Order references alias the selected vector elements. book returns sorted eligible indices, other selects the opposite side, and front chooses its head afresh each loop. Both order remainders are reduced by the fill, while only maker visible quantity is reduced. The stream insertion after tradeLine precedes refresh. Postincrement assigns a new sequence value. Standard sort/reference/continue semantics avoid unrelated implementation.

## Minimization and alternatives

Reviewed the excerpt independently against the four shared requirements. The alternative of including the entire matching routine, all order/trader declarations, post-order placement, and command dispatch adds unrelated accounting, history, risk checks, and order types. Selected only the comparison/selection contract, control-flow boundaries, quantity and priority changes, relevant fee position, and output-producing lines; field access and standard collection/minimum/control-flow semantics supply the rest. Book/history reporting and initial iceberg acceptance are unnecessary because the question begins with an existing resting iceberg order. Custom selection, fill, and output helpers are followed only where their semantics are necessary; unused helper bodies and routine closing punctuation with no additional scope information are omitted.

The excerpt contains 1303 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
