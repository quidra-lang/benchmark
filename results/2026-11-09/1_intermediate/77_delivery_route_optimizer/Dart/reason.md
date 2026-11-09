# Task B selection — Dart

## Answer requirements shared across languages

1. Trace the ordered route through coordinate lookup,Manhattan distance,depot departure,consecutive stop legs and depot return to its exact integer total.
2. Use depot (0,0) and stop (3,4) to explain coordinate units and total 14; explain empty route=0,equal-coordinate distinct stops and whether any rounding occurs.

## Selected source locations

- `main.dart`: 37, 38, 39, 40, 41, 42, 43, 44, 45, 46

## Evidence and language semantics

point resolves id 0 to depot and other ids to stops. length wraps the list with 0 at both ends and accumulates consecutive distance calls; abs and int operations are exact. A stop at (3,4) relative to (0,0) costs |3|+|4|=7 coordinate units each way,and the one-stop route totals 14. An empty route adds only depot-to-depot,so total is 0. Distinct ids at equal coordinates remain distinct visits but the leg between them is 0; no positive-distance minimum or coordinate deduplication is applied. There is no division,square root,unit scale or rounding step in this operation.

## Minimization and alternatives

The coordinate lookup,distance formula,ordered accumulator and closing leg are the complete necessary operation. The custom absolute/lookup helper is included where language semantics alone cannot establish it. Route optimization,time scheduling,formatting and callers are unnecessary. A distance-only alternative would omit depot closure and empty-route behavior; the length routine alone would hide metric/units.

The excerpt contains 210 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
