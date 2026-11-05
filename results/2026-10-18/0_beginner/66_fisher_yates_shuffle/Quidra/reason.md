# Task B selection: 66_fisher_yates_shuffle / Quidra

The deck construction determines each original card. The seed, loop bounds, update, index and unconditional tuple assignment establish the two iterations, exact integer arithmetic and unchanged RNG consumption. The output partitioning runs after the shuffle.

The selected lines are verbatim and in source order. The excerpt uses the task assumptions and the documented semantics of the imported APIs.

Task A: 198 tokens. Task B: 159 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 198; Task B 159.

Measurement: Task A 198; Task B 159. Tokenizer: metric/tokenizer.py, unchanged.
