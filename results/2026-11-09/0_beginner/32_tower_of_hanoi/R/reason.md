# Task B: 32_tower_of_hanoi / R

For (4,A,C,B), first solve (3,A,B,C), emit the move of disk 4 from A to C, then solve (3,B,C,A). At disk count zero the base case returns zero and emits no move. The returned count is left count +1+ right count =15. Peg letters are role arguments, not shared mutable peg storage; rebinding a callee role does not change the caller bindings.

The function recurses with character values in independent parameter bindings; no shared peg collection is modified.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L10.

- L1: `hanoi <- function(n, source, target, auxiliary) {`
- L2: `if (n == 0) {`
- L3: `return(0)`
- L4: `}`
- L5: `moves <- hanoi(n - 1, source, auxiliary, target)`
- L6: `cat(sprintf("move disk %d from %s to %s\n", n, source, target))`
- L7: `moves + 1 + hanoi(n - 1, auxiliary, target, source)`
- L8: `}`
- L10: `moves <- hanoi(4, "A", "C", "B")`

Minimization: The recursive routine, base case, move output and top-level role assignment are needed. Unrelated summary formatting is omitted where it is a separate statement. The selected complete original lines, in source order, cost 155 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 156, and the complete source costs 177. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
