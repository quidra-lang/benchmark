# Task B selection — Go

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.go`: 361, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 621

## Evidence and language semantics

The resolver literal supplies an empty cache and 1/86400/3600 settings; omitted int clock has Go zero value 0. store takes the minimum TTL, clamps using MINTTL/MAXTTL, then stores expiry=r.clock+ttl. NEGTTL is a default duration but unused here.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 275 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
