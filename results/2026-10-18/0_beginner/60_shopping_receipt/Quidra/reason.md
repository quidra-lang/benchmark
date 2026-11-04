# Task B selection: 60_shopping_receipt / Quidra

## Answer requirements

Trace actual food items into the food total and category-level truncated tax; follow that tax into payment and distinguish untaxed item subtotals.

## Answer supported by the selected source

The food entries are milk 198*2=396, bread 248*1=248, apple 128*4=512 and eggs 268*1=268, totaling 1424. The source accumulates these subtotals before the later `food_tax := food_total * 8 / 100`, so integer division truncates once to 113 at the category level. The payment formula adds food_tax alongside both category totals and general_tax. The earlier per-item print uses subtotal, before the food tax is computed, so those item lines are untaxed.

## Evidence and alternatives

The parallel arrays identify actual items, prices, quantities and food membership. The food accumulator, item loop, subtotal, food condition/update and item print establish inputs and untaxed display. The food-tax expression and final total formula establish truncation and payment flow. General-category initialization/update/tax calculation do not affect any requested food value, and final summary printing adds no calculation evidence. The full original excerpt was considered and contains those unrelated dependencies. General-category numeric totals need not be calculated to explain the food-tax contribution.

Selected complete main.qui source lines: 1, 2, 3, 4, 5, 7, 8, 9, 10, 13, 14, 16. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 4edefba77b30a2a7d55e2849f30e2d022fb1f6b2d12d7319f45293830459555a): Task A 353 tokens; Task B 249 tokens. Original values: Task A 368; Task B 260. Task B proposed modifications have not been implemented. Lexical counts or excerpt review do not by themselves establish compilation or correctness.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 353; Task B 249.

Measurement: Task A 353; Task B 249. Tokenizer: metric/tokenizer.py, unchanged.
