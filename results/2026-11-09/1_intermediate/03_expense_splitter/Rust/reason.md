# Task B selection — Rust

## Answer requirements shared across languages

1. Trace a signed integer cent balance through sign selection, absolute-cent conversion and two-digit fraction formatting in BALANCES.
2. State the member-line representation for 7, -7 and 0 cents, including indentation.

## Selected source locations

- `main.rs`: 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 611, 615, 616, 617, 618, 619

## Evidence and language semantics

signed_money chooses +money(n), -money(-n) or literal zero. Integer division and {:02} format the magnitude in money. The multiline member format starts with two spaces and passes the signed balance as its second argument. Thus the balance texts are +0.07, -0.07 and 0.00; with member name N the lines are "  N +0.07", "  N -0.07" and "  N 0.00".

## Minimization and alternatives

Only the member output line and its actual formatting dependencies are needed. Balance computation, active-member ordering and other reports are excluded because the input is already a signed integer cent balance. Custom quotient/padding/wrapper bodies are included where required; native abs, integer division, remainder and formatting use language/library semantics. The member-line literal is necessary to establish indentation independently of numeric formatting.

The excerpt contains 235 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
