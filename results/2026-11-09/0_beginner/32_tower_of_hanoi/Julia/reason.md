# Task B: 32_tower_of_hanoi / Julia

For (4,A,C,B), first solve (3,A,B,C), emit the move of disk 4 from A to C, then solve (3,B,C,A). At disk count zero the base case returns zero and emits no move. The returned count is left count +1+ right count =15. Peg letters are role arguments, not shared mutable peg storage; rebinding a callee role does not change the caller bindings.

The recursive function passes immutable string labels by value/reference without mutating them; each invocation has its own argument bindings.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L8.

- L1: `function hanoi(n, source, target, auxiliary)`
- L2: `n == 0 && return 0`
- L3: `moves = hanoi(n-1, source, auxiliary, target)`
- L4: `println("move disk ", n, " from ", source, " to ", target)`
- L5: `return moves + 1 + hanoi(n-1, auxiliary, target, source)`
- L8: `println("total moves: ", hanoi(4, "A", "C", "B"))`

Minimization: The recursive routine, base case, move output and top-level role assignment are needed. Unrelated summary formatting is omitted where it is a separate statement. The selected complete original lines, in source order, cost 143 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 146, and the complete source costs 146. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
