# Task B selection — C++

## Answer requirements shared across languages

1. Trace a signed integer cent balance through sign selection, absolute-cent conversion and two-digit fraction formatting in BALANCES.
2. State the member-line representation for 7, -7 and 0 cents, including indentation.

## Selected source locations

- `main.cpp`: 77, 78, 79, 80, 81, 82, 432, 435

## Evidence and language semantics

signedMoney returns literal 0.00 for zero, otherwise selects sign and passes the nonnegative magnitude to money. money divides by 100 and prepends a zero when the remainder is below ten. Member output begins with two spaces. Thus the balance texts are +0.07, -0.07 and 0.00; with member name N the lines are "  N +0.07", "  N -0.07" and "  N 0.00".

## Minimization and alternatives

Only the member output line and its actual formatting dependencies are needed. Balance computation, active-member ordering and other reports are excluded because the input is already a signed integer cent balance. Custom quotient/padding/wrapper bodies are included where required; native abs, integer division, remainder and formatting use language/library semantics. The member-line literal is necessary to establish indentation independently of numeric formatting.

The excerpt contains 219 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
