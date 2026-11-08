# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace integer cents through whole-unit quotient, cent remainder, literal decimal separator, and two-digit zero padding.
2. Compare 5 cents -> 0.05 and 0 cents -> 0.00, and distinguish the amount text from surrounding BILL labels.

## Selected source locations

- `main.rb`: 15, 16, 223

## Evidence and language semantics

Integer division and remainder feed format %d.%02d. For 5, the quotient is 0 and remainder 5; for 0 both are 0. The selected decimal separator and width-two zero padding therefore produce 0.05 and 0.00. The selected SUBTOTAL consumer supplies the bill label separately from the conversion.

## Minimization and alternatives

The formatter operations and one BILL consumer supply all requested facts. Selecting other bill fields or the full BILL routine repeats the same conversion. Arithmetic that computes bill totals, parsing, and payment processing are unrelated. Helper bodies are included only where custom numeric formatting needs them; standard formatting/padding semantics need no implementation.

The excerpt contains 53 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
