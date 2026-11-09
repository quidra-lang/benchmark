# Task B selection — Julia

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.jl`: 175, 176, 177, 178, 179, 180, 181, 186, 187, 188, 189, 190, 191, 192, 193, 301, 303

## Evidence and language semantics

The positional Resolver constructor aligns clock with 0, cache with an empty Dict and settings with the named 1/86400/3600 defaults. positive! clamps the minimum record TTL between MINTTL/MAXTTL and stores clock+ttl in the entry. NEGTTL is not part of the positive clamp.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 221 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
