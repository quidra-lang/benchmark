# Task B selection — R

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.R`: 6, 7, 8, 159, 160, 161, 163, 178, 179, 180, 181, 182, 183, 184, 185, 186, 228, 229, 231, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 246, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 337, 338, 339, 340, 341, 342, 343, 347, 348, 349, 350, 351, 352, 353, 354, 355, 421, 422, 423, 424

## Evidence and language semantics

The environment constructor explicitly uses new.env, whose reference semantics make a selected caller frame mutable even when held in a local R variable. Values are scalar numeric results in a variables list. Lookup walks rev(seq_along(...)); make searches only frames two and above and otherwise assigns frame one. Inputs are evaluated before new_environment(setNames(...)) is appended. LOCAL and LOCALMAKE change the last frame. logo_return constructs an error condition; OUTPUT therefore unwinds WHILE/execute to the matching tryCatch, whose finally removes the last frame. Earlier caller/global writes survive that removal.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 1053 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
