# Task B selection — Java

## Answer requirements shared across languages

1. Trace a signed integer argument -0 through optional-sign recognition, decimal-digit/length acceptance, and numeric conversion.
2. Compare 0 and a negative nonzero argument, identifying the local rejection checks before obtaining the converted value; do not confuse this with calendar-date range validation.

## Selected source locations

- `Main.java`: 76, 77, 374, 375, 541

## Evidence and language semantics

String.matches matches the whole token, require throws on failure, and Integer.parseInt produces integer 0 for -0. The selected integer-argument path accepts an optional leading minus and requires one through seven decimal digits. Thus -0 and 0 pass the same digit checks, while e.g. -7 converts to negative seven. Empty sign-only input, nondigits, or excess digits fail the local lexical check. The selected conversion supplies the value used by ADD; date conversion and supported-date ranges are separate operations.

## Minimization and alternatives

The signed-number validation and numeric construction are the complete local evidence. Where custom validators wrap regex/digit predicates, their rejection operation is included. Unit checks, calendar compatibility and later date arithmetic do not determine normalization of the integer token and are excluded. Standard numeric parsers supply sign and digit conversion without their library source.

The excerpt contains 97 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
