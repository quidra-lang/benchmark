# Task B selection — C#

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `Program.cs`: 20, 22, 353, 356, 374, 376, 377, 382, 384, 385, 386, 387, 388, 389, 392, 399, 400, 468, 472, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 490, 577, 579, 582, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 726, 728

## Evidence and language semantics

C# dictionary lookup and ContainsKey preserve zero-valued bindings and reverse frame priority. Call constructs a new parameter Environment, Execute evaluates command expressions first, and LOCAL/LOCALMAKE target environments[^1]. A Flow exception from OUTPUT unwinds WHILE and list execution; Call catches it, reads its value, and removes the last environment. Surviving reference objects retain mutations. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 947 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
