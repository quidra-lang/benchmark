# Task B selection — R

## Answer requirements shared across languages

1. Trace DR and CR with amount token 0.07 through side recognition, local acceptance checks and construction of the journal-line record.
2. Identify side separately from integer cents 7, explain why changing side does not require a negative amount token, and distinguish parsing from later posting validation.

## Selected source locations

- `main.R`: 19, 20, 21, 156, 157, 365, 366, 367, 368

## Evidence and language semantics

posting_line builds separate debit and amount list values; parse_cents uses gmp big integers for the whole-value cents result. Parsing 0.07 computes 0*100+7, so both DR and CR store positive integer cents 7. The side value changes independently. The local guard requires an open draft; this stage constructs/appends the line rather than posting it. No additional positivity, account, balancing, or decimal-format rejection should be invented for the shown local block; input-shape assumptions and standard integer parser semantics apply.

## Minimization and alternatives

The excerpt keeps amount conversion, side construction, open-draft rejection and local record insertion. Custom constructors are included only to show side/amount storage; standard record/aggregate constructors need no implementation. Full POST validation, signed balance calculations, formatting and journal queries are outside this local parsing question.

The excerpt contains 273 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
