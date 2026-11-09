# Task B selection — C

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.c`: 57, 58, 61, 561, 573, 574, 575, 576, 577

## Evidence and language semantics

Static storage zero-initializes now and cache_count; the cache starts empty. min_ttl=1,max_ttl=86400,neg_ttl=3600 are settings. store takes the minimum record TTL, clamps it to min_ttl/max_ttl and passes now+ttl as the expiry argument. NEGTTL is not read on this positive path.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 271 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
