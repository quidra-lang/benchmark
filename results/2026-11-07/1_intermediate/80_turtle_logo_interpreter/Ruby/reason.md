# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.rb`: 13, 14, 16, 17, 249, 250, 251, 252, 253, 254, 255, 256, 257, 307, 308, 310, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 326, 329, 330, 331, 400, 401, 402, 403, 404, 405, 406, 410, 411, 412, 413, 414, 415, 416, 417, 418, 473, 474, 475, 476

## Evidence and language semantics

Ruby reverse.find yields the nearest environment hash; MAKE excludes the global during local search then falls back to the first environment. Parameters are zipped to a new hash. LOCAL/LOCALMAKE write the last environment. LogoReturn escapes execute and the WHILE until loop; call rescues its value and ensure removes the environment/call entry. A hash referenced by a caller remains mutated after the callee hash is popped. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 663 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
