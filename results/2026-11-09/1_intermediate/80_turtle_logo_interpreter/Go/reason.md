# Task B selection — Go

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.go`: 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 374, 375, 379, 380, 381, 382, 383, 384, 474, 478, 487, 488, 489, 490, 491, 492, 493, 494, 495, 503, 504, 505, 506, 507, 638, 639, 640, 641, 642, 643, 644, 645, 646, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 676, 785, 786, 787, 788, 789, 790, 791, 792

## Evidence and language semantics

Pointer receiver methods and the freshly allocated *environment with map[string]int64 establish mutable frame identity and scalar values. assign searches local indexes from the end and writes the global map only after none contain the key. Expression arguments are evaluated before call pushes parameter bindings. OUTPUT returns a control pointer; WHILE and sequence pass that pointer upward, and call removes the callee frame before returning the output scalar. No caller or global map is rolled back.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 986 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
