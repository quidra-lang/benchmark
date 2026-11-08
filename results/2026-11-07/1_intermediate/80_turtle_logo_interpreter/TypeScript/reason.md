# Task B selection — TypeScript

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.ts`: 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 497, 498, 502, 508, 509, 510, 511, 512, 513, 514, 515, 520, 522, 525, 526, 527, 528, 529, 530, 601, 602, 603, 604, 606, 608, 609, 610, 611, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 707, 708, 709, 710, 711, 712, 713, 714, 715, 728, 729

## Evidence and language semantics

The TypeScript types annotate the same explicit Map/array environment algorithm. has/get establishes dynamic lookup even for zero. A new Map binds evaluated arguments to parameters; local-only reverse MAKE search falls back to the global Map. OUTPUT is a returned Flow, forwarded by command sequences and WHILE and unwrapped after the frame is removed. The excerpt does not assume lexical closure scoping.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 1043 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
