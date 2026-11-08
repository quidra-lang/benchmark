# Task B selection — Python

## Answer requirements shared across languages

1. Identify separate empty-cell, numeric-zero and #VALUE! representations at a cell read.
2. Trace the read branches and a numeric consumer: empty converts to numeric zero there, numeric zero stays numeric, and an error is propagated rather than conflated with either value.
3. Explain why conversion is context-dependent and the underlying stored cases remain distinguishable.

## Selected source locations

- `main.py`: 44, 422, 423, 424, 425, 426, 429, 430, 431, 432, 433, 434, 573, 574, 575, 576, 577, 578, 586, 587, 588

## Evidence and language semantics

The selected reference/cell-read path returns the stored value. Empty is represented by a missing/nullable value in the nullable implementations, by Empty/Z in the tagged implementations, or by Node::Empty in Rust. A numeric zero is an N/num/Int variant carrying 0, while #VALUE! is an E/err/Error value carrying that exact error text. The numeric conversion branch maps only the empty representation to numeric zero, rejects text/ranges as #VALUE!, and returns existing numeric/error values unchanged. The selected unary numeric consumer calls that conversion and explicitly propagates an error instead of applying negation. Therefore an empty cell and numeric zero can yield the same numeric operand without being the same stored value; an error remains distinct. Standard optional/null, dictionary get, array, enum/match and tagged-value semantics support the distinction. For J/Zig the selected cell reader also exposes the separate formula-result coercion; this is evaluation of a formula result, not erasure of all blank-cell storage. 

## Minimization and alternatives

Only value constructors/tags, the local cell-read branch, numeric conversion and one actual numeric consumer are retained. Dependency graphs, SCC/cycle construction, formula parsing, user formatting and other numeric functions do not change the three-case distinction. The unary consumer is smaller than selecting a complete binary-operator or aggregate routine while still proving conversion plus error propagation. Direct constructors are smaller evidence for numeric/error identity than following SET parsing. Initial/default value lines or direct nonformula copies are included where needed to make blank storage explicit.

The excerpt contains 244 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
