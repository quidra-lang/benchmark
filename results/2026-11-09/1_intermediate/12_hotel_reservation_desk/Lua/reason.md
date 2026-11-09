# Task B selection — Lua

## Answer requirements shared across languages

1. Identify the actual command-error exit path and the control-flow edge permitting subsequent waitlist processing.
2. Determine whether that edge depends on command success.

## Selected source locations

- `main.lua`: 877, 878, 879, 880, 881, 882, 883, 884, 885, 886, 887

## Evidence and language semantics

pcall converts command failure into ok=false. A recognized reason table emits ERROR and falls through after the if to process_waitlist. Unrecognized failures are rethrown; the ordinary error-reporting edge is unconditional with respect to success.

## Minimization and alternatives

The selected error-reporting exit and immediately following queue edge answer the local question. Waitlist admission internals, unrelated command cases and success-output construction cannot change this control-flow fact. For plain-return implementations, a concrete command return and its caller are needed; for caught errors the catch/fallthrough itself suffices. Zig's explicit failure branch is smaller and more direct than its successful-command path.

The excerpt contains 101 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
