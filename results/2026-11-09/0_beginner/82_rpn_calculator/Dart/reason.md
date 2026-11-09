Each expression starts with an empty operand stack. Expression 2 pushes -17 and 5, pops right b=5 then left a=-17 and divides toward zero to -3; it then pushes 4,-3, multiplies to -12 and subtracts -3-(-12)=9. Underflow is checked before pops, divisor zero before result push, and final stack size must be one. Errors stop further token updates.

A fresh <int>[] is allocated per expression. removeLast reads b before a; ~/ truncates toward zero, and stack.add receives the operation result. break bypasses later token updates while error==null protects the leftover check.

Fresh operand stack, token conversion, pop order, toward-zero division, error exits and final-size check establish expression 2 and every requested guard. Other expression outputs are omitted.
