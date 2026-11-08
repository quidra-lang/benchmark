# Task B selection — Lua

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.lua`: 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 325, 326, 329, 330, 331, 332, 333, 334, 335, 409, 413, 422, 423, 424, 425, 426, 427, 428, 429, 430, 438, 534, 535, 536, 537, 538, 539, 540, 541, 543, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 665, 666, 667, 668, 669, 670, 671, 672

## Evidence and language semantics

Lua tables have reference identity and zero is truthy; ~=nil therefore tests binding existence even when LOCAL stores zero. assign searches through index two before its global index-one fallback. The scalar arguments are evaluated before call constructs a fresh variables table and binds parameters. OUTPUT creates a signal table that sequence and WHILE propagate with immediate returns. call removes the last environment and consumes the output signal; changes to earlier environment tables remain.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 843 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
