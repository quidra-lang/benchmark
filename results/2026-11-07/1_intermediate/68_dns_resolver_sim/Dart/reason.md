# Task B selection — Dart

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.dart`: 71, 264, 265, 266, 267, 268, 269, 270, 482, 483, 484, 485, 486, 488, 489, 490, 491, 492, 493, 494

## Evidence and language semantics

The settings map initializes MINTTL=1,MAXTTL=86400,NEGTTL=3600; clock=0 and cache={}. positive finds the minimum record TTL and clamps it with the first two settings before constructing CacheEntry whose expiry parameter is clock+seconds. NEGTTL is not consulted.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 300 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
