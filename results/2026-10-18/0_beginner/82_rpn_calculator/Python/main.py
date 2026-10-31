expressions = [
    "3 4 + 2 *",
    "-17 5 / 4 -3 * -",
    "1 2 + * 3",
    "15 7 1 1 + - / 3 * 2 1 1 + + -",
    "4 2 5 * + 1 3 2 * - 5 + /",
    "2 3 4 + 5",
    "46341 46339 * -2 /",
]
for expression in expressions:
    stack = []
    error = None
    for token in expression.split():
        if token not in {"+", "-", "*", "/"}:
            stack.append(int(token))
            continue
        if len(stack) < 2:
            error = "stack underflow"
            break
        b, a = stack.pop(), stack.pop()
        if token == "/" and b == 0:
            error = "division by zero"
            break
        if token == "+":
            result = a + b
        elif token == "-":
            result = a - b
        elif token == "*":
            result = a * b
        else:
            result = int(a / b)
        stack.append(result)
    if error is None and len(stack) != 1:
        error = "leftover operands"
    answer = f"error: {error}" if error else str(stack[0])
    print(f"{expression} => {answer}")
