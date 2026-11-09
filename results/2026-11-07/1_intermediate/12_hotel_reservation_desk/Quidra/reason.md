# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the actual command-error exit path and the control-flow edge permitting subsequent waitlist processing.
2. Determine whether that edge depends on command success.

## Selected source locations

- `main.qui`: 88, 89, 295, 311, 312, 313, 708, 709

## Evidence and language semantics

The unknown-room path prints ERROR through fail and returns from command. Its input-loop caller then calls process_waitlist(&hotel) unconditionally; command success is not checked.

## Minimization and alternatives

The selected error-reporting exit and immediately following queue edge answer the local question. Waitlist admission internals, unrelated command cases and success-output construction cannot change this control-flow fact. For plain-return implementations, a concrete command return and its caller are needed; for caught errors the catch/fallthrough itself suffices. Zig's explicit failure branch is smaller and more direct than its successful-command path.

The excerpt contains 93 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
