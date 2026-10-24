"""Brace validation and recursive descent into the prescribed syntax nodes."""

from lexer import FormulaError


ATOM_KINDS = frozenset(("identifier", "number", "symbol", "command", "text"))
TERMINATORS = frozenset(("}", "&", "newline", "right", "end", "eof"))
ARGUMENT_KINDS = ATOM_KINDS | frozenset((
    "eqref", "{", "frac", "binom", "overset", "underset", "sqrt", "accent",
))
UNEXPECTED = {
    "right": r"unexpected \right", "end": r"unexpected \end",
    "&": "misplaced &", "newline": r"misplaced \\",
}


class Node:
    def __init__(self, kind, children=(), value=None, column=0):
        self.kind = kind
        self.children = children
        self.value = value
        self.column = column


def collapse(elements):
    return elements[0] if len(elements) == 1 else Node("row", tuple(elements))


def check_braces(tokens):
    stack = []
    for token in tokens:
        if token.kind == "{":
            stack.append(token.column)
        elif token.kind == "}":
            if not stack:
                raise FormulaError(token.column, "unmatched }")
            stack.pop()
    if stack:
        raise FormulaError(stack[-1], "unclosed {")


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0
        self.tag = self.label = None

    def peek(self):
        return self.tokens[self.position]

    def take(self):
        token = self.peek()
        if token.kind != "eof":
            self.position += 1
        return token

    def unexpected(self):
        token = self.peek()
        raise FormulaError(token.column, UNEXPECTED[token.kind])

    def parse(self):
        elements = self.element_list(top=True)
        if self.peek().kind != "eof":
            self.unexpected()
        return elements

    def element_list(self, top=False, index=False):
        elements = []
        while True:
            token = self.peek()
            if token.kind in TERMINATORS or index and token.kind == "symbol" and token.value == "]":
                return elements
            if token.kind in ("tag", "label"):
                if not top:
                    raise FormulaError(token.column, "misplaced \\" + token.kind)
                if getattr(self, token.kind) is not None:
                    raise FormulaError(token.column, "duplicate \\" + token.kind)
                setattr(self, token.kind, self.take())
                continue
            elements.append(self.element())

    def element(self):
        base = Node("row") if self.peek().kind in ("^", "_") else self.nucleus()
        subscript = superscript = None
        while self.peek().kind in ("^", "_"):
            token = self.take()
            if token.kind == "^":
                if superscript is not None:
                    raise FormulaError(token.column, "double superscript")
                superscript = self.argument("^")
            else:
                if subscript is not None:
                    raise FormulaError(token.column, "double subscript")
                subscript = self.argument("_")
        if subscript is None and superscript is None:
            return base
        return Node("script", (base, subscript, superscript))

    def argument(self, name):
        if self.peek().kind not in ARGUMENT_KINDS:
            raise FormulaError(self.peek().column, "missing argument for " + name)
        return self.nucleus()

    def delimiter(self):
        token = self.take()
        if token.kind == "symbol" and token.value in ("(", ")", "[", "]", "|", "."):
            return token.value
        if token.kind == "command" and token.value in (r"\{", r"\}"):
            return token.value
        raise FormulaError(token.column, "invalid delimiter")

    def nucleus(self):
        token = self.take()
        kind = token.kind
        if kind in ATOM_KINDS:
            return Node(kind, value=token.value, column=token.column)
        if kind == "eqref":
            return Node("reference", value=token.value, column=token.column)
        if kind == "{":
            elements = self.element_list()
            if self.peek().kind != "}":
                self.unexpected()
            self.take()
            return collapse(elements)
        if kind in ("frac", "binom", "overset", "underset"):
            first = self.argument("\\" + kind)
            second = self.argument("\\" + kind)
            return Node(kind, (first, second))
        if kind == "sqrt":
            index = None
            if self.peek().kind == "symbol" and self.peek().value == "[":
                opening = self.take()
                elements = self.element_list(index=True)
                if self.peek().kind != "symbol" or self.peek().value != "]":
                    raise FormulaError(opening.column, "missing ]")
                self.take()
                index = collapse(elements)
            body = self.argument(r"\sqrt")
            return Node("sqrt", (body,)) if index is None else Node("root", (index, body))
        if kind == "accent":
            return Node("accent", (self.argument("\\" + token.value),), value=token.value)
        if kind == "left":
            left = self.delimiter()
            elements = self.element_list()
            if self.peek().kind != "right":
                raise FormulaError(token.column, r"missing \right")
            closing = self.take()
            right = self.delimiter()
            return Node("delim", (collapse(elements),), value=(left, right), column=closing.column)
        return self.matrix(token.value, token.column)

    def matrix(self, environment, column):
        rows = [[]]
        while True:
            rows[-1].append(collapse(self.element_list()))
            token = self.take()
            if token.kind == "&":
                continue
            if token.kind == "newline":
                rows.append([])
                continue
            if token.kind != "end":
                raise FormulaError(column, r"missing \end")
            if token.value != environment:
                raise FormulaError(token.column, r"mismatched \end")
            break
        if (len(rows) >= 2 and len(rows[-1]) == 1
                and rows[-1][0].kind == "row" and not rows[-1][0].children):
            rows.pop()
        columns = max(len(row) for row in rows)
        for row in rows:
            row.extend(Node("row") for unused in range(columns - len(row)))
        return Node("matrix", tuple(tuple(row) for row in rows), value=environment)
