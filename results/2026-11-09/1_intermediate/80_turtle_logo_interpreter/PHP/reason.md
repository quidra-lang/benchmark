# Task B selection — PHP

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.php`: 27, 29, 299, 303, 333, 334, 335, 339, 340, 341, 342, 343, 344, 345, 413, 415, 416, 417, 418, 422, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 446, 449, 450, 451, 452, 453, 454, 455, 456, 457, 558, 559, 560, 561, 562, 563, 564, 565, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 585, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707

## Evidence and language semantics

Environment object handles preserve identity in the stack despite PHP array value semantics. array_key_exists establishes binding membership, so a zero local is present. make updates the nearest local object or global object; LOCAL/LOCALMAKE address the last object. call evaluates arguments before constructing a new parameter array and Environment. OUTPUT throws LogoReturn through nested execute calls and WHILE; the catch reads its value and finally pops the callee environment. Prior writes to surviving object properties remain. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed.

The excerpt contains 1194 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
