# Task B selection — Python

## Answer requirements shared across languages

1. Trace DR and CR with amount token 0.07 through side recognition, local acceptance checks and construction of the journal-line record.
2. Identify side separately from integer cents 7, explain why changing side does not require a negative amount token, and distinguish parsing from later posting validation.

## Selected source locations

- `main.py`: 93, 94, 95, 138, 139, 141, 267, 268, 269, 270, 396, 397, 398, 399, 402, 405

## Evidence and language semantics

The DR/CR wrappers pass separate side strings. Line stores side unchanged and amount unchanged; cents computes the amount with Python ints. Parsing 0.07 computes 0*100+7, so both DR and CR store positive integer cents 7. The side value changes independently. The local guard requires an open draft; this stage constructs/appends the line rather than posting it. No additional positivity, account, balancing, or decimal-format rejection should be invented for the shown local block; input-shape assumptions and standard integer parser semantics apply.

## Minimization and alternatives

The excerpt keeps amount conversion, side construction, open-draft rejection and local record insertion. Custom constructors are included only to show side/amount storage; standard record/aggregate constructors need no implementation. Full POST validation, signed balance calculations, formatting and journal queries are outside this local parsing question.

The excerpt contains 262 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
