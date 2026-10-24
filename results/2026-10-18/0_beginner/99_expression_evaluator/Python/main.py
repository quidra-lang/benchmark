import re


class Parser:
    def __init__(self, tokens, variables):
        self.tokens = tokens
        self.variables = variables
        self.index = 0

    def peek(self):
        return self.tokens[self.index] if self.index < len(self.tokens) else ""

    def factor(self):
        token = self.peek()
        self.index += 1
        if token == "-":
            return -self.factor()
        if token == "(":
            value = self.expression()
            self.index += 1
            return value
        if token.isdigit():
            return int(token)
        if token not in self.variables:
            raise ValueError(f"undefined variable {token}")
        return self.variables[token]

    def term(self):
        value = self.factor()
        while self.peek() in ("*", "/"):
            operation = self.peek()
            self.index += 1
            right = self.factor()
            if operation == "*":
                value *= right
            else:
                if right == 0:
                    raise ValueError("division by zero")
                value = int(value / right)
        return value

    def expression(self):
        value = self.term()
        while self.peek() in ("+", "-"):
            operation = self.peek()
            self.index += 1
            right = self.term()
            value = value + right if operation == "+" else value - right
        return value


lines = [
    "width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
    "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus",
    "volume = area * depth", "width = (width+3)*-(2-4)", "width * shift - height",
]
variables = {}
for line in lines:
    tokens = re.findall(r"\d+|[a-z]+|[-+*/()=]", line)
    name = tokens[0] if len(tokens) > 1 and tokens[1] == "=" else None
    expression = tokens[2:] if name else tokens
    try:
        value = Parser(expression, variables).expression()
        if name:
            variables[name] = value
            print(f"{name} = {value}")
        else:
            print(value)
    except ValueError as error:
        print(f"error: {error}")
