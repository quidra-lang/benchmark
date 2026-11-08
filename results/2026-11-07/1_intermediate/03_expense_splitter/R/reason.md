# Task B selection — R

## Answer requirements shared across languages

1. Trace a signed integer cent balance through sign selection, absolute-cent conversion and two-digit fraction formatting in BALANCES.
2. State the member-line representation for 7, -7 and 0 cents, including indentation.

## Selected source locations

- `main.R`: 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 17, 18, 21, 22, 325, 328

## Evidence and language semantics

signed_text returns literal zero, otherwise picks + or - and formats abs(value). amount_text uses floor_div and a %02d cent remainder. paste joins its first argument, a single-space string, to the name with its default separating space, producing two leading spaces. Thus the balance texts are +0.07, -0.07 and 0.00; with member name N the lines are "  N +0.07", "  N -0.07" and "  N 0.00".

## Minimization and alternatives

Only the member output line and its actual formatting dependencies are needed. Balance computation, active-member ordering and other reports are excluded because the input is already a signed integer cent balance. Custom quotient/padding/wrapper bodies are included where required; native abs, integer division, remainder and formatting use language/library semantics. The member-line literal is necessary to establish indentation independently of numeric formatting.

The excerpt contains 256 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
