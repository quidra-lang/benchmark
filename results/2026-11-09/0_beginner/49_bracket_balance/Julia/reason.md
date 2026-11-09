# Task B: 49_bracket_balance / Julia

The scanner retains original character positions. The plus sign is neither an opening bracket nor a recognized closing bracket, so both recognition branches fail and no stack operation runs. It still occupies zero-based position 3 (one-based ordinal 4) in `(a + b) * [c - d]`; nonbrackets have not been filtered and renumbered.

enumerate(expression) supplies original one-based positions; the reported position expression subtracts 1. Opening membership and haskey(matching,c) ignore +.

Evidence is from `main.jl`, L10,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23.

- L10: `matching = Dict(')' => '(', ']' => '[', '}' => '{')`
- L14: `for (position, c) in enumerate(text)`
- L15: `if c in ('(', '[', '{')`
- L16: `push!(stack, c)`
- L17: `elseif haskey(matching, c)`
- L18: `if isempty(stack) || stack[end] != matching[c]`
- L19: `error_index = position-1`
- L20: `break`
- L21: `end`
- L22: `pop!(stack)`
- L23: `end`

Minimization: The recognition tables/conditions, original scanning index and branch boundaries are needed to show that plus triggers no stack path. Unrelated error/output handling is omitted where possible. The selected complete original lines, in source order, cost 166 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 192, and the complete source costs 442. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
