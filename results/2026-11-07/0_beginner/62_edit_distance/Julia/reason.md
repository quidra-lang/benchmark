# Task B: 62_edit_distance / Julia

At prefix lengths 2,2 the characters are i and i, so replacement cost is zero. The neighboring-prefix candidates are deletion 3, insertion 3 and substitution/match 1; the cell minimum is 1. A character match changes only the replacement cost. The minimum expression still evaluates all three candidates; there is no branch that skips deletion/insertion arithmetic on a match.

The ternary computes only cost (0 or 1); min then evaluates its three arithmetic arguments under ordinary eager function-call semantics.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8.

- L1: `function edit_distance(a, b)`
- L2: `table = zeros(Int, length(a)+1, length(b)+1)`
- L3: `table[:, 1] = 0:length(a)`
- L4: `table[1, :] = 0:length(b)`
- L5: `for i = 1:length(a), j = 1:length(b)`
- L6: `cost = a[i] == b[j] ? 0 : 1`
- L7: `table[i+1, j+1] = min(table[i, j+1]+1, table[i+1, j]+1, table[i, j]+cost)`
- L8: `end`

Minimization: Initialization, the relevant prefix loops and the cell expression are retained because they establish the concrete neighboring values. No final-distance printing or unrelated string pairs are required. The selected complete original lines, in source order, cost 183 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 183, and the complete source costs 312. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
