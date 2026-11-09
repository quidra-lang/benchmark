# Task B selection — R

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.R`: 7, 8, 9, 228, 230

## Evidence and language semantics

cache starts empty,settings contain MINTTL=1,MAXTTL=86400,NEGTTL=3600 and clock=0. store clamps the minimum record ttl between MINTTL/MAXTTL and stores expiry=clock+ttl. NEGTTL is a duration default,unused here.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 170 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
