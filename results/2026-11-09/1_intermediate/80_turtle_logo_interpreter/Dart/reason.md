# Task B selection — Dart

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.dart`: 80, 81, 83, 86, 87, 88, 89, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 541, 542, 546, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 566, 569, 570, 572, 573, 574, 575, 576, 638, 639, 640, 641, 642, 643, 646, 647, 648, 649, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 747, 748, 749, 750, 751, 752, 753, 754, 755, 769, 770

## Evidence and language semantics

Dart maps and Environment objects retain reference identity, while the variable values are ints. The reverse containsKey search excludes frame zero for MAKE and uses it as global fallback; lookup uses all active frames. call evaluates inputs before adding a fresh parameter map. The current getter and LOCAL/LOCALMAKE map writes establish shadowing. OUTPUT returns Flow; WHILE and sequence return it immediately, then call removes the last frame. Only that frame is discarded; mutations in other map objects remain. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 975 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
