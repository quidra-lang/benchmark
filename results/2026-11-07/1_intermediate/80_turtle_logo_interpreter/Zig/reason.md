# Task B selection — Zig

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.zig`: 4, 8, 9, 10, 311, 312, 323, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 414, 416, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 441, 535, 536, 537, 538, 539, 540, 541, 542, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 663, 664, 665, 666, 667, 668, 669, 670

## Evidence and language semantics

The selected i64 alias and StringHashMapUnmanaged values establish scalar bindings. The stack holds *Environment pointers; assign mutates the nearest map pointer found, while no match writes global index zero. Inputs evaluate before a fresh allocated Environment is pushed and parameters are inserted. LOCAL/LOCALMAKE mutate current(), the last stack pointer. OUTPUT is a non-error optional Signal, returned through WHILE and sequence; call pops the callee, deinitializes its map and destroys its allocation before returning the scalar. Earlier writes to other allocated frames remain. equal is included because command identity otherwise depends on a custom helper.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 1444 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
