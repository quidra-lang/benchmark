# Task B: 33_yen_change / Julia

For original 506, the 500-yen iteration obtains quotient 1 and remainder 6, emits the 500×1 item and adds one to the piece total. At 100 yen the quotient is zero and remainder stays 6; the positive-count guard suppresses that item and adds nothing. The changing remainder is a different binding from the retained original amount used in the line label.

remaining,total and pieces are per-input state. divrem updates only remaining; the original amount reaches the final println.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11.

- L1: `for amount in [3780, 15420, 99999, 506, 48263]`
- L2: `remaining, total = amount, 0`
- L3: `pieces = String[]`
- L4: `for face in [10000, 5000, 1000, 500, 100, 50, 10, 5, 1]`
- L5: `quantity, remaining = divrem(remaining, face)`
- L6: `if quantity > 0`
- L7: `push!(pieces, string(face, "x", quantity))`
- L8: `total += quantity`
- L9: `end`
- L10: `end`
- L11: `println(amount, " yen: ", join(pieces, " "), " (", total, " pieces)")`

Minimization: The input/original label, remainder initialization, denomination order, quotient/remainder update and nonzero branch are needed. Later denomination cases need no separate enumeration. The selected complete original lines, in source order, cost 218 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 218, and the complete source costs 220. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
