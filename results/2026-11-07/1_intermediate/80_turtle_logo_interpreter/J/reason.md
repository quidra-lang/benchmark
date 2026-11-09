# Task B selection — J

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.ijs`: 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 279, 280, 281, 282, 283, 284, 285, 290, 292, 293, 294, 295, 426, 427, 428, 429, 430, 431, 433, 434, 435, 436, 440, 507, 508, 509, 510, 511, 525, 526, 527, 528, 529, 530

## Evidence and language semantics

J boxed arrays explicitly represent the frame stack. The custom bind verb inserts a new name or amends an existing numeric value and writes that boxed frame back to global EnvBindings, so no reference-semantics assumption is needed. lookup reverses all frame indexes; makeVariable reverses local indexes only and falls back to zero. callProcedure evaluates arguments before appending parameter names and values. LOCAL uses zero and the final frame; LOCALMAKE evaluates its expression there. OUTPUT returns a two-item signal with tag two, propagated by WHILE/runList, and callProcedure removes only the final frame with }: before returning its value.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 769 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
