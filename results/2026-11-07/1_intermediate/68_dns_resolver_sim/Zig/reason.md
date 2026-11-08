# Task B selection — Zig

## Answer requirements shared across languages

1. Identify initial clock=0,empty cache,MINTTL=1,MAXTTL=86400 and NEGTTL=3600 in source.
2. Trace the local positive-cache TTL calculation to show the initialized minimum/maximum bounds it reads before SET and distinguish those duration settings from stored absolute expiry.

## Selected source locations

- `main.zig`: 301, 303, 304, 305, 306, 494, 495, 496, 497

## Evidence and language semantics

The resolver field defaults give an empty cache,clock=0 and TTL values 1/86400/3600. store takes minimum ttl,clamps by minttl/maxttl and constructs a positive entry with expiry=self.clock+ttl. negttl is not read on this path.

## Minimization and alternatives

The initialization and positive-store data dependency suffice. Source declarations/constructor signatures or field-index mapping are retained only where positional storage would otherwise obscure clock/settings/expiry. Record sorting, DNS traversal, command parsing, setting mutation and negative-cache implementation are unnecessary. Selecting defaults alone would omit their actual use; selecting the whole resolver would add unrelated work.

The excerpt contains 229 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
