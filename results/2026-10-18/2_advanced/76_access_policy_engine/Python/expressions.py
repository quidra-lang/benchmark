"""Tokenization and recursive-descent parsing of the policy expression grammar."""

import re


TOKENS = re.compile(r'"[^"]*"|[0-9]+|[A-Za-z][A-Za-z0-9_.]*|==|!=|<=|>=|[()\[\],+*<>-]')


class Parser:
    def __init__(self, text):
        self.tokens = TOKENS.findall(text)
        self.position = 0

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def take(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def joined(self, next_level, operators):
        expression = next_level()
        while self.peek() in operators:
            operator = self.take()
            expression = (operator, expression, next_level())
        return expression

    def disjunction(self):
        return self.joined(self.conjunction, ("or",))

    def conjunction(self):
        return self.joined(self.negation, ("and",))

    def negation(self):
        if self.peek() == "not":
            self.take()
            return "not", self.negation()
        return self.comparison()

    def comparison(self):
        expression = self.sum()
        if self.peek() in ("==", "!=", "<", "<=", ">", ">=", "in"):
            operator = self.take()
            expression = operator, expression, self.sum()
        return expression

    def sum(self):
        return self.joined(self.product, ("+", "-"))

    def product(self):
        return self.joined(self.unary, ("*",))

    def unary(self):
        if self.peek() == "-":
            self.take()
            return "-", self.unary()
        return self.primary()

    def primary(self):
        token = self.take()
        if token.isdigit():
            return "literal", int(token)
        if token.startswith('"'):
            return "literal", token[1:-1]
        if token in ("true", "false"):
            return "literal", token == "true"
        if token == "it":
            return ("it",)
        if "." in token:
            return "attribute", token
        if token == "(":
            expression = self.disjunction()
            self.take()
            return expression
        if token == "[":
            values = []
            while self.peek() != "]":
                values.append(self.take()[1:-1])
                if self.peek() != "]":
                    self.take()
            self.take()
            return "literal", tuple(values)
        self.take()
        arguments = []
        while self.peek() != ")":
            arguments.append(self.disjunction())
            if self.peek() != ")":
                self.take()
        self.take()
        return (token, *arguments)


def parse(text):
    return Parser(text).disjunction()
