# Task B selection: 61_coin_change_dp / Quidra

## Answer requirements

Locate ways initialization and coin-first recurrence; explain amount-first dynamic programming for ordered sequences while leaving denominations, targets, minimum count, greedy count and output fields unchanged.

## Answer supported by the selected source

Keep ways[0]=1 and zero positive entries. Make increasing positive amount the outer traversal through maximum; inside it visit every coin not exceeding the amount and add ways[amount-coin]. Each predecessor sequence plus that final coin gives one ordered sequence, so different final-coin orders count separately. The shared table serves all unchanged target lookups. The minimum table, greedy calculation and output do not need changes for Task B.

## Evidence and alternatives

The allocation, zero-amount seed, coin-outer header, bounded amount-inner header and update are precisely the affected state and recurrence. Literal denominations, target initialization, maximum derivation, minimum DP, greedy loop and output remain unchanged for this modification and add no necessary source evidence. Recomputing tables separately per target was considered; one maximum-sized table has identical prefix results and eliminates repeated work.

Selected complete main.qui source lines: 10, 11, 12, 13, 14. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 4edefba77b30a2a7d55e2849f30e2d022fb1f6b2d12d7319f45293830459555a): Task A 334 tokens; Task B 77 tokens. Original values: Task A 343; Task B 77. Task B proposed modifications have not been implemented. Native validation of Task A is recorded separately in validation-results.json; lexical counts or excerpt review do not by themselves establish compilation or correctness.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 334; Task B 77.
