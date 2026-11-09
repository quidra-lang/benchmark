# Task B selection — C

## Answer requirements shared across languages

1. Identify the actual command-error exit path and the control-flow edge permitting subsequent waitlist processing.
2. Determine whether that edge depends on command success.

## Selected source locations

- `main.c`: 513, 516, 517, 518, 1055, 1056

## Evidence and language semantics

A duplicate-room error prints ERROR then returns from command, not main. The caller unconditionally calls process_waitlist immediately after command; no success condition is tested.

## Minimization and alternatives

The selected error-reporting exit and immediately following queue edge answer the local question. Waitlist admission internals, unrelated command cases and success-output construction cannot change this control-flow fact. For plain-return implementations, a concrete command return and its caller are needed; for caught errors the catch/fallthrough itself suffices. Zig's explicit failure branch is smaller and more direct than its successful-command path.

The excerpt contains 89 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
