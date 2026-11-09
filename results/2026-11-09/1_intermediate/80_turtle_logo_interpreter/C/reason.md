# Task B selection — C

## Answer requirements shared across languages

1. Trace dynamic lookup from the innermost active procedure environment through caller environments to globals, including evaluated arguments and fresh parameter bindings.
2. Explain MAKE updating the nearest existing active local binding, or creating/updating a global when no local binding exists.
3. Explain LOCAL and LOCALMAKE in the current callee environment, including zero initialization versus an evaluated value and their effect on later lookup and MAKE.
4. Follow OUTPUT inside a loop through signal/exception propagation and procedure environment cleanup; distinguish mutations of surviving caller/global bindings from discarded callee bindings.

## Selected source locations

- `main.c`: 81, 82, 83, 84, 85, 86, 87, 88, 89, 94, 95, 96, 97, 98, 99, 100, 101, 613, 614, 615, 618, 619, 620, 621, 622, 623, 630, 633, 634, 635, 636, 637, 638, 639, 641, 642, 643, 644, 645, 652, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 678, 681, 682, 683, 684, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 924, 925, 926, 927, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1061, 1062, 1063, 1064, 1065, 1069, 1072, 1073, 1074, 1075, 1076, 1077

## Evidence and language semantics

The explicit environment_count stack and pointers to Environment establish which stored variables change. variable_index and set_variable distinguish update from insertion, and make excludes index zero while searching locals before its global fallback. evaluate obtains scalar long long arguments before call appends a fresh zeroed frame and inserts parameters. OUTPUT has Flow.kind 2; the WHILE and command sequence return any nonzero kind immediately. call frees only the callee map and decrements the stack count, so earlier writes to caller/global slots survive. The selected frame/flow declarations establish the stored scalar type or constructor-field relationship rather than relying on a custom class name.

## Minimization and alternatives

The common scenario uses a caller parameter x, a nested callee, and OUTPUT from a WHILE body. Before a callee-local declaration, MAKE x updates the caller binding; LOCAL x shadows it with zero, or LOCALMAKE x installs its supplied value, so later MAKE x affects the callee binding. A fresh name becomes global. The selected loop and sequence/call handling establish OUTPUT propagation and removal of the callee frame. Examined the alternative of including all loop kinds, the parser, turtle drawing, arithmetic reporters, tracing and complete environment classes; those add no information required by this scenario. Only evaluated-input/parameter binding, nearest-binding search, local dispatch and necessary signal/cleanup lines remain. Standard map/list/exception semantics supply ordinary mechanics. The final excerpt was separately read against all four requirements; source locations are copied verbatim, and no execution or modification is claimed. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1374 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
