Each expression starts with an empty operand stack. Expression 2 pushes -17 and 5, pops right b=5 then left a=-17 and divides toward zero to -3; it then pushes 4,-3, multiplies to -12 and subtracts -3-(-12)=9. Underflow is checked before pops, divisor zero before result push, and final stack size must be one. Errors stop further token updates.

Each evaluate call allocates a new stack. table.remove pops b then a; absolute integer division plus sign restoration truncates negative results toward zero. Early return stops all later updates and the final length test rejects leftovers.

Fresh operand stack, token conversion, pop order, toward-zero division, error exits and final-size check establish expression 2 and every requested guard. Other expression outputs are omitted.
