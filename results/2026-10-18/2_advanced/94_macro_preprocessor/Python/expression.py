"""Parse integer preprocessing expressions and evaluate only selected branches."""

import re
import sys


LEVELS = (("||",), ("&&",), ("|",), ("^",), ("&",), ("==", "!="),
          ("<", ">", "<=", ">="), ("<<", ">>"), ("+", "-"), ("*", "/", "%"))


class ExpressionError(Exception):
    pass


def integer_value(spelling):
    value = spelling
    for suffix in ("ll", "LL", "l", "L"):
        if value.endswith(suffix) and len(value) > len(suffix):
            value = value[:-len(suffix)]
            break
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", value):
        return int(value, 16)
    if re.fullmatch(r"0[0-7]*", value):
        return int(value, 8)
    if re.fullmatch(r"[1-9][0-9]*", value):
        return int(value)
    raise ExpressionError(f'invalid integer constant "{spelling}"')


def character_value(spelling):
    value = spelling[1:-1]
    if len(value) == 1 and value not in "'\\":
        return ord(value)
    escapes = {"n": 10, "t": 9, "\\": 92, "'": 39, '"': 34, "0": 0}
    if len(value) == 2 and value[0] == "\\" and value[1] in escapes:
        return escapes[value[1]]
    raise ExpressionError("invalid character constant " + spelling)


class Parser:
    def __init__(self, tokens):
        self.tokens, self.position = tokens, 0

    def peek(self):
        return self.tokens[self.position].spelling if self.position < len(self.tokens) else None

    def expression(self):
        left = self.binary(0)
        if self.peek() == "?":
            self.position += 1
            first = self.expression()
            if self.peek() != ":":
                raise ExpressionError("'?' without following ':'")
            self.position += 1
            left = ("conditional", left, first, self.expression())
        return left

    def binary(self, level):
        if level == len(LEVELS):
            return self.unary()
        left = self.binary(level + 1)
        while self.peek() in LEVELS[level]:
            operator = self.peek()
            self.position += 1
            left = ("binary", operator, left, self.binary(level + 1))
        return left

    def unary(self):
        if self.peek() in ("+", "-", "!", "~"):
            operator = self.peek()
            self.position += 1
            return "unary", operator, self.unary()
        if self.position == len(self.tokens):
            raise ExpressionError("expected value at end of expression")
        token = self.tokens[self.position]
        self.position += 1
        if token.kind == "number":
            return "constant", integer_value(token.spelling)
        if token.kind == "character":
            return "constant", character_value(token.spelling)
        if token.kind == "identifier":
            return "identifier", token.spelling
        if token.spelling == "(":
            value = self.expression()
            if self.peek() != ")":
                raise ExpressionError("missing ')' in expression")
            self.position += 1
            return value
        raise ExpressionError(f'expected value before "{token.spelling}"')


def parse(tokens, directive):
    if not tokens:
        raise ExpressionError("#" + directive + " with no expression")
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 14 * len(tokens) + 1000))
    parser = Parser(tokens)
    tree = parser.expression()
    if parser.peek() is not None:
        raise ExpressionError(f'missing binary operator before "{parser.peek()}"')
    return tree


def binary_value(operator, first, second):
    if operator in ("/", "%"):
        if second == 0:
            raise ExpressionError("division by zero in #if")
        quotient = abs(first) // abs(second)
        if (first < 0) != (second < 0):
            quotient = -quotient
        return quotient if operator == "/" else first - second * quotient
    if operator == "+":
        return first + second
    if operator == "-":
        return first - second
    if operator == "*":
        return first * second
    if operator == "<<":
        return first << second
    if operator == ">>":
        return first >> second
    if operator == "&":
        return first & second
    if operator == "|":
        return first | second
    if operator == "^":
        return first ^ second
    comparisons = {"==": first == second, "!=": first != second, "<": first < second,
                   ">": first > second, "<=": first <= second, ">=": first >= second}
    return int(comparisons[operator])


def evaluate(tree, warning):
    pending, values = [("evaluate", tree)], []
    while pending:
        operation, item = pending.pop()
        if operation == "evaluate":
            kind = item[0]
            if kind == "constant":
                values.append(item[1])
            elif kind == "identifier":
                warning(f'identifier "{item[1]}" evaluates to 0')
                values.append(0)
            elif kind == "unary":
                pending.extend([("unary", item[1]), ("evaluate", item[2])])
            elif kind == "conditional":
                pending.extend([("choose", (item[2], item[3])), ("evaluate", item[1])])
            elif item[1] in ("&&", "||"):
                pending.extend([("logical", (item[1], item[3])), ("evaluate", item[2])])
            else:
                pending.extend([("binary", item[1]), ("evaluate", item[3]), ("evaluate", item[2])])
        elif operation == "choose":
            pending.append(("evaluate", item[0] if values.pop() != 0 else item[1]))
        elif operation == "logical":
            first = values.pop()
            if item[0] == "&&" and first == 0 or item[0] == "||" and first != 0:
                values.append(int(first != 0))
            else:
                pending.extend([("truth", None), ("evaluate", item[1])])
        elif operation == "truth":
            values.append(int(values.pop() != 0))
        elif operation == "unary":
            value = values.pop()
            values.append(value if item == "+" else -value if item == "-" else int(value == 0) if item == "!" else -value - 1)
        else:
            second, first = values.pop(), values.pop()
            values.append(binary_value(item, first, second))
    return values[0]
