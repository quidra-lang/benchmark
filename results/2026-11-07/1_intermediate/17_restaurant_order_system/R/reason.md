# Task B selection — R

## Answer requirements shared across languages

1. Trace integer cents through whole-unit quotient, cent remainder, literal decimal separator, and two-digit zero padding.
2. Compare 5 cents -> 0.05 and 0 cents -> 0.00, and distinguish the amount text from surrounding BILL labels.

## Selected source locations

- `main.R`: 7, 8, 9, 10, 263

## Evidence and language semantics

floor supplies the quotient; integer_text formats it without scientific notation. The remainder uses %% and sprintf %02d, joined by paste0 with the literal dot. For 5, the quotient is 0 and remainder 5; for 0 both are 0. The selected decimal separator and width-two zero padding therefore produce 0.05 and 0.00. The selected SUBTOTAL consumer supplies the bill label separately from the conversion.

## Minimization and alternatives

The formatter operations and one BILL consumer supply all requested facts. Selecting other bill fields or the full BILL routine repeats the same conversion. Arithmetic that computes bill totals, parsing, and payment processing are unrelated. Helper bodies are included only where custom numeric formatting needs them; standard formatting/padding semantics need no implementation.

The excerpt contains 117 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
