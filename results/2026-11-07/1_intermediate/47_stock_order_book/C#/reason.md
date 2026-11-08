# Task B selection — C#

## Answer requirements shared across languages

1. Identify the eligible best opposite-side resting order by price and time priority, and repeat that choice after each match or cancellation.
2. Trace consumption of the visible slice and remaining quantity, then replenishment to min(peak, remaining) with new time priority when hidden quantity remains.
3. Establish TRADE-before-REFRESH output order and explain that the next eligible best order can be another order at the same price.
4. For a best resting order owned by the incoming trader, identify the resting-order cancellation, retained incoming quantity, and the control flow that skips trade, fees, and refresh.

## Selected source locations

- `Program.cs`: 23, 27, 28, 49, 88, 89, 91, 92, 94, 96, 97, 98, 99, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 118, 121, 122, 123, 124, 125, 126, 127, 128, 129, 131, 132, 135, 136, 137, 138

## Evidence and language semantics

The match loop reselects the best opposite-side order each iteration. The ordering key prioritizes the best price and then the oldest priority. A fill consumes the smaller of the incoming remainder and the maker visible slice; the retained maker remainder is the hidden-plus-visible quantity. Exhausting a slice with a positive remainder assigns a fresh priority and exposes min(peak, remainder), placing it behind older resting orders at the same price. The trade output is produced before that refresh output. The same-trader guard cancels the resting maker and continues before fill, fee, and refresh processing, so the incoming remainder is not consumed. C# Order is used as a mutable object reference: both the book selection and Fill operate on the same object. LINQ OrderBy/ThenBy and FirstOrDefault establish the exact priority rule. Fill subtraction and ordered List.Add calls establish remaining quantity and output sequencing; continue bypasses trade and fee work.

## Minimization and alternatives

Reviewed the excerpt independently against the four shared requirements. The alternative of including the entire matching routine, all order/trader declarations, post-order placement, and command dispatch adds unrelated accounting, history, risk checks, and order types. Selected only the comparison/selection contract, control-flow boundaries, quantity and priority changes, relevant fee position, and output-producing lines; field access and standard collection/minimum/control-flow semantics supply the rest. Book/history reporting and initial iceberg acceptance are unnecessary because the question begins with an existing resting iceberg order. Custom selection, fill, and output helpers are followed only where their semantics are necessary; unused helper bodies and routine closing punctuation with no additional scope information are omitted.

The excerpt contains 938 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
