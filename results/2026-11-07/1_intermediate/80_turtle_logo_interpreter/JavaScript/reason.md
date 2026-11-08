# Task B selection — JavaScript

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.js`: 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 417, 418, 422, 428, 429, 430, 431, 432, 433, 434, 435, 440, 442, 445, 446, 447, 448, 449, 450, 521, 522, 523, 524, 526, 528, 529, 530, 531, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 627, 628, 629, 630, 631, 632, 633, 634, 635, 648, 649

## Evidence and language semantics

JavaScript Map.has distinguishes an existing zero binding from absence. Parameters form a new Map, and the array retains caller frames. MAKE searches from the tail down to local index 1 then writes global index 0. LOCAL writes current().variables, so it shadows the caller. OUTPUT is a Flow object returned through sequence and WHILE, then consumed by call before popping its environment; mutation of earlier Map objects survives.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 941 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
