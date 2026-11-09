# Task B selection — Python

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.py`: 60, 61, 62, 63, 115, 116, 118, 365, 370, 371, 372, 373, 374, 375, 376, 380, 381, 427, 428, 429, 446, 447, 448, 449, 450, 451, 452, 453, 454, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 518, 519, 520, 521, 522, 523, 524, 525, 529, 531, 532, 535, 536, 543, 544

## Evidence and language semantics

lookup walks reversed active environments, and make uses the first matching Environment or the global object. The callee parameters are bound in a fresh dictionary after argument evaluation. LOCAL writes zero and LOCALMAKE an evaluated value into only the last environment. OUTPUT raises ProcedureExit; WHILE and run_list do not catch it, so call_procedure catches the value and then pops its environment. Dictionary/object reference semantics preserve writes to the caller/global environment; pop discards only the callee binding map. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 812 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
