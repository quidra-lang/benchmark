# Task B selection — Kotlin

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.kt`: 202, 204, 220, 221, 222, 223, 224, 228, 229, 230, 231, 232, 233, 236, 238, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 255, 258, 261, 262, 264, 383, 384, 387, 388, 389, 390, 391, 392, 393, 405, 407, 441, 442, 443, 451

## Evidence and language semantics

Kotlin reversed traversal of mutable maps performs dynamic lookup; nullable map access is safe here because stored values are non-null Long values. Parameters get a fresh mutable map. MAKE updates the nearest containing frame or globals; LOCAL/LOCALMAKE select envs.last. Flow is thrown by OUTPUT, passes through execute and WHILE, and is caught by invoke before removing the current environment. Earlier map mutations are retained. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 773 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
