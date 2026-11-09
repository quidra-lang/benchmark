# Task B selection — Swift

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.swift`: 312, 313, 314, 315, 316, 317, 318, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 365, 369, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 395, 398, 399, 403, 404, 405, 572, 573, 574, 575, 578, 579, 580, 581, 582, 583, 584, 585, 586, 602, 603, 604, 605, 606, 607, 652, 653, 654, 655, 656, 657, 669, 670

## Evidence and language semantics

Environment is a class with [String:Int] values, so frame references persist through array access; the parameter dictionary is newly constructed from scalar values. Reverse lookup includes callers, while MAKE searches local indexes and uses global index zero as fallback. Command expressions are evaluated before invoke pushes a callee Environment. LOCAL and LOCALMAKE address envs.last. OUTPUT throws Flow.output; Swift throws/try propagates it through WHILE and execute to the invocation catch, followed by removeLast. Removing that class object from the stack leaves caller/global objects and their earlier changes intact.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 899 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
