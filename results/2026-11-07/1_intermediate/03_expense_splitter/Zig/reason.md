# Task B selection — Zig

## Answer requirements shared across languages

1. Trace a signed integer cent balance through sign selection, absolute-cent conversion and two-digit fraction formatting in BALANCES.
2. State the member-line representation for 7, -7 and 0 cents, including indentation.

## Selected source locations

- `main.zig`: 17, 18, 19, 21, 22, 23, 512, 517

## Evidence and language semantics

signedMoney special-cases zero; otherwise it selects sign and a nonnegative magnitude. money casts the magnitude to u64 and formats division by 100 plus width-two remainder. Member format begins with two spaces. Thus the balance texts are +0.07, -0.07 and 0.00; with member name N the lines are "  N +0.07", "  N -0.07" and "  N 0.00".

## Minimization and alternatives

Only the member output line and its actual formatting dependencies are needed. Balance computation, active-member ordering and other reports are excluded because the input is already a signed integer cent balance. Custom quotient/padding/wrapper bodies are included where required; native abs, integer division, remainder and formatting use language/library semantics. The member-line literal is necessary to establish indentation independently of numeric formatting.

The excerpt contains 325 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
