# Task B selection — Java

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `Main.java`: 33, 34, 36, 37, 365, 367, 398, 399, 400, 405, 406, 407, 408, 409, 410, 413, 418, 419, 476, 478, 479, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 499, 572, 573, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 649, 650, 651, 652, 664, 665

## Evidence and language semantics

Java environments carry mutable maps and remain ordered in the active list. containsKey controls nearest-binding lookup/update; argument expressions are evaluated before Call binds parameters in a new Environment. LOCAL uses the current final frame. OUTPUT throws Flow and the command/WHILE chain lets it reach call, which obtains the value and removes the last environment. It neither rolls back outer maps nor leaves callee bindings active. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 984 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
