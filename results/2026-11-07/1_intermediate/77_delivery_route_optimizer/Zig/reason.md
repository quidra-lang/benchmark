# Task B selection — Zig

## Answer requirements shared across languages

1. Trace the ordered route through coordinate lookup,Manhattan distance,depot departure,consecutive stop legs and depot return to its exact integer total.
2. Use depot (0,0) and stop (3,4) to explain coordinate units and total 14; explain empty route=0,equal-coordinate distinct stops and whether any rounding occurs.

## Selected source locations

- `main.zig`: 4, 16, 17, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118

## Evidence and language semantics

distance selects depot for 0 and otherwise stored stop coordinates; custom abs is retained. length walks ordered ids from last=0,total=0 and includes the final depot leg; Int is i64 and no rounding is performed. A stop at (3,4) relative to (0,0) costs |3|+|4|=7 coordinate units each way,and the one-stop route totals 14. An empty route adds only depot-to-depot,so total is 0. Distinct ids at equal coordinates remain distinct visits but the leg between them is 0; no positive-distance minimum or coordinate deduplication is applied. There is no division,square root,unit scale or rounding step in this operation.

## Minimization and alternatives

The coordinate lookup,distance formula,ordered accumulator and closing leg are the complete necessary operation. The custom absolute/lookup helper is included where language semantics alone cannot establish it. Route optimization,time scheduling,formatting and callers are unnecessary. A distance-only alternative would omit depot closure and empty-route behavior; the length routine alone would hide metric/units.

The excerpt contains 295 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
