Each expression starts with an empty operand stack. Expression 2 pushes -17 and 5, pops right b=5 then left a=-17 and divides toward zero to -3; it then pushes 4,-3, multiplies to -12 and subtracts -3-(-12)=9. Underflow is checked before pops, divisor zero before result push, and final stack size must be one. Errors stop further token updates.

stack << pushes, pop order binds b then a, and quo(...).truncate preserves truncation toward zero. break exits on errors and error.nil? protects the leftover test from overwriting an earlier error.

Fresh operand stack, token conversion, pop order, toward-zero division, error exits and final-size check establish expression 2 and every requested guard. Other expression outputs are omitted.
