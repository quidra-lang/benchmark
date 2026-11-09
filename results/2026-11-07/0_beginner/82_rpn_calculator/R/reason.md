# Task B: 82_rpn_calculator / R

Each evaluation starts with an empty stack and no error. Expression 2 pushes -17 and 5, pops right=5 then left=-17, truncates division toward zero to -3 and pushes it. Next 4 and -3 multiply to -12, then subtraction pops right=-12 and left=-3, producing 9; the sole remaining operand is the result. Underflow is checked before pops, zero divisor before division, and final stack length must be one. Each error exits/halts this evaluation before further stack updates.

The function starts a fresh vector stack, removes its final two operands in right/left order, uses trunc(a/b), and returns immediately on guarded errors.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28,L29,L31,L32.

- L1: `evaluate <- function(expression) {`
- L2: `stack <- numeric(0)`
- L3: `for (token in strsplit(expression, " ", fixed = TRUE)[[1]]) {`
- L4: `if (token %in% c("+", "-", "*", "/")) {`
- L5: `if (length(stack) < 2) {`
- L6: `return("error: stack underflow")`
- L7: `}`
- L8: `b <- tail(stack, 1)`
- L9: `a <- stack[length(stack) - 1]`
- L10: `stack <- head(stack, -2)`
- L11: `if (token == "/" && b == 0) {`
- L12: `return("error: division by zero")`
- L13: `}`
- L14: `value <- switch(token,`
- L15: `"+" = a + b,`
- L16: `"-" = a - b,`
- L17: `"*" = a * b,`
- L18: `"/" = trunc(a / b)`
- L19: `)`
- L20: `stack <- c(stack, value)`
- L21: `} else {`
- L22: `stack <- c(stack, as.numeric(token))`
- L23: `}`
- L24: `}`
- L25: `if (length(stack) == 1) sprintf("%d", stack[1]) else "error: leftover operands"`
- L28: `expressions <- c(`
- L29: `"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",`
- L31: `)`
- L32: `for (expression in expressions) cat(sprintf("%s => %s\n", expression, evaluate(expression)))`

Minimization: The actual second-expression literal and its iteration binding/evaluator call are necessary to derive the -17,5 sequence from source rather than Task A requirements. Other expressions are omitted unless they share that physical source line. The evaluator entry, stack updates and guarded error/result operations establish the requested trace and error boundaries; unrelated program wrappers are excluded. Complete source lines remain verbatim and in order. No Task A program was built or executed.
