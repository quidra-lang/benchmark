# Task B selection: 54_max_subarray / Quidra

## Answer requirements

Trace array 2 through 10 and -2; explain restarting versus extending, saved starting/end indices, and why later candidate updates need not change the recorded best range.

## Answer supported by the selected source

The candidate/best starts -4/-4, then becomes 7/7, 6/7, 9/9, 1/9, 11/11 at 10 and 9/11 at -2. Negative current triggers restarting at the 7. The candidate at 10 extends the prior sum 1 and retains start 1; the strict best update stores [1,5]. At -2 the candidate falls to 9 but the saved best remains 11. Scalar copies keep candidate and best indices independent.

## Evidence and alternatives

The selected array prefix identifies array 2 and supplies all traced data. Initial values, loop order, restart and extension branches, strict best guard and saved-index assignments support every requested state transition. Final printing and array 3 are unnecessary. The old arithmetic guard was considered and is equivalent for exact int; the new guard is shorter while directly expressing the decision.

Selected complete main.qui source lines: 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 4edefba77b30a2a7d55e2849f30e2d022fb1f6b2d12d7319f45293830459555a): Task A 373 tokens; Task B 284 tokens. Original values: Task A 383; Task B 294. Task B proposed modifications have not been implemented. Native validation of Task A is recorded separately in validation-results.json; lexical counts or excerpt review do not by themselves establish compilation or correctness.
