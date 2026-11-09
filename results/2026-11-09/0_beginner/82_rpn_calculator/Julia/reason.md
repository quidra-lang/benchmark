# Task B: 82_rpn_calculator / Julia

Each evaluation starts with an empty stack and no error. Expression 2 pushes -17 and 5, pops right=5 then left=-17, truncates division toward zero to -3 and pushes it. Next 4 and -3 multiply to -12, then subtraction pops right=-12 and left=-3, producing 9; the sole remaining operand is the result. Underflow is checked before pops, zero divisor before division, and final stack length must be one. Each error exits/halts this evaluation before further stack updates.

The evaluate function allocates a fresh stack, uses pop! right then left, div for truncating signed division and immediate error returns.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L26,L28,L34,L35.

- L1: `function evaluate(expression)`
- L2: `stack = Int[]`
- L3: `for token in split(expression)`
- L4: `if token in ("+", "-", "*", "/")`
- L5: `length(stack) < 2 && return "error: stack underflow"`
- L6: `b = pop!(stack)`
- L7: `a = pop!(stack)`
- L8: `token == "/" && b == 0 && return "error: division by zero"`
- L9: `if token == "+"`
- L10: `value = a+b`
- L11: `elseif token == "-"`
- L12: `value = a-b`
- L13: `elseif token == "*"`
- L14: `value = a*b`
- L15: `else`
- L16: `value = div(a, b)`
- L17: `end`
- L18: `push!(stack, value)`
- L19: `else`
- L20: `push!(stack, parse(Int, token))`
- L21: `end`
- L22: `end`
- L23: `return length(stack) == 1 ? string(stack[1]) : "error: leftover operands"`
- L26: `for expression in [`
- L28: `"-17 5 / 4 -3 * -",`
- L34: `]`
- L35: `println(expression, " => ", evaluate(expression))`

Minimization: The actual second-expression literal and its iteration binding/evaluator call are necessary to derive the -17,5 sequence from source rather than Task A requirements. Other expressions are omitted unless they share that physical source line. The evaluator entry, stack updates and guarded error/result operations establish the requested trace and error boundaries; unrelated program wrappers are excluded. Complete source lines remain verbatim and in order. No Task A program was built or executed.
