# Task B selection — Python

## Answer requirements shared across languages

1. Locate the binary required-field presence predicate and the field type/value representation needed to recognize a present uint32 zero.
2. Explain extending only that predicate to fail for absent fields or REQUIRED uint32 zero, retaining all other field types and text-literal checks.

## Selected source locations

- `main.py`: 129, 232, 233, 234, 235, 236, 284, 285, 286, 287, 288, 289

## Evidence and language semantics

message.has checks membership, while get obtains the stored scalar. Use field.type_name == "uint32" and message.get(field) == 0; do not change has or the broad field.kind integer classifier. Keep required as the outer guard and short-circuit the absent check before indexing/accessing the first value. The edit is local to this binary required-check routine; generic storage presence and the separate text-literal seen-field validation must retain their existing behavior.

## Minimization and alternatives

Selected lines expose the current predicate and the exact type/value access needed for the extension. Binary decoding loops, encoding, nested-message traversal bodies, error formatting helpers, and text parsing are not needed to identify this local edit. Changing the generic presence helper or treating every numeric zero as missing would be broader than requested. No implementation is changed.

The excerpt contains 178 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
