# Task B selection — PHP

## Answer requirements shared across languages

1. Locate the binary required-field presence predicate and the field type/value representation needed to recognize a present uint32 zero.
2. Explain extending only that predicate to fail for absent fields or REQUIRED uint32 zero, retaining all other field types and text-literal checks.

## Selected source locations

- `main.php`: 6, 605, 606, 607, 608, 609, 610, 611, 612

## Evidence and language semantics

required reads a PHP value array; field->type->kind is the enum discriminator and UInt32 values are integers. Add that guard with values[0] === 0. Keep required as the outer guard and short-circuit the absent check before indexing/accessing the first value. The edit is local to this binary required-check routine; generic storage presence and the separate text-literal seen-field validation must retain their existing behavior.

## Minimization and alternatives

Selected lines expose the current predicate and the exact type/value access needed for the extension. Binary decoding loops, encoding, nested-message traversal bodies, error formatting helpers, and text parsing are not needed to identify this local edit. Changing the generic presence helper or treating every numeric zero as missing would be broader than requested. No implementation is changed.

The excerpt contains 201 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
