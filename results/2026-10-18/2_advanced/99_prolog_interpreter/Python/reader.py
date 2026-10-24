"""Prolog tokens and the fixed-priority clause reader."""

import sys
from dataclasses import dataclass

from terms import Compound, Variable, make_list


SYMBOLS = set("+-*/\\^<>=~:.?@#&$")
INFIX = {}
for priority, kind, names in [
    (1200, "xfx", [":-"]), (1100, "xfy", [";"]), (1050, "xfy", ["->"]),
    (1000, "xfy", [","]),
    (700, "xfx", ["=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=.."]),
    (500, "yfx", ["+", "-"]), (400, "yfx", ["*", "/", "//", "mod", "rem"]),
]:
    for name in names:
        INFIX[name] = (priority, priority if kind == "yfx" else priority - 1,
                       priority if kind == "xfy" else priority - 1)
PREFIX = {"\\+": 900, "-": 200}


@dataclass
class Token:
    kind: str
    value: object
    spelling: str
    line: int
    column: int
    space: bool
    index: int


class SyntaxError(Exception):
    def __init__(self, token, message=None):
        self.token = token
        if message is None:
            if token.kind == "invalid":
                message = token.value
            elif token.kind == "eof":
                message = "unexpected end of file"
            elif token.kind == "end":
                message = "unexpected end of clause"
            elif token.kind == "name" and token.value in INFIX:
                message = "operator priority clash"
            else:
                message = f'unexpected "{token.spelling}"'
        self.message = message


def tokenize(text, column=1):
    tokens = []
    position, line, space = 0, 1, True
    while position < len(text):
        character = text[position]
        if character in " \n":
            if character == "\n":
                line, column = line + 1, 1
            else:
                column += 1
            position += 1
            space = True
            continue
        if character == "%":
            end = text.find("\n", position)
            end = len(text) if end == -1 else end
            column += end - position
            position = end
            space = True
            continue
        start, start_column = position, column
        if character.isdigit():
            position += 1
            while position < len(text) and text[position].isdigit():
                position += 1
            value = int(text[start:position])
            kind = "integer"
            if value > 2147483647:
                kind, value = "invalid", "integer too large"
        elif character.isalpha() or character == "_":
            position += 1
            while position < len(text) and (text[position].isalnum() or text[position] == "_"):
                position += 1
            value = text[start:position]
            kind = "name" if character.islower() else "variable"
        elif character in SYMBOLS:
            position += 1
            while position < len(text) and text[position] in SYMBOLS:
                position += 1
            value = text[start:position]
            kind = "end" if value == "." and (position == len(text) or text[position] in " \n%") else "name"
        elif character in "!;":
            kind, value = "name", character
            position += 1
        elif character in ",|()[]":
            kind, value = "punct", character
            position += 1
        elif character == "'":
            position += 1
            represented = []
            incorrect = False
            while True:
                if position == len(text) or text[position] == "\n":
                    kind, value = "invalid", "unterminated quoted atom"
                    break
                current = text[position]
                if current == "'":
                    if position + 1 < len(text) and text[position + 1] == "'":
                        represented.append("'")
                        position += 2
                    else:
                        position += 1
                        kind = "invalid" if incorrect else "quoted"
                        value = "undefined escape sequence" if incorrect else "".join(represented)
                        break
                elif current == "\\":
                    position += 1
                    if position < len(text) and text[position] != "\n":
                        escape = text[position]
                        if escape not in "nt\\'":
                            incorrect = True
                        represented.append({"n": "\n", "t": "\t", "\\": "\\", "'": "'"}.get(escape, escape))
                        position += 1
                else:
                    represented.append(current)
                    position += 1
        else:
            kind, value = "invalid", f"illegal character '{character}'"
            position += 1
        tokens.append(Token(kind, value, text[start:position], line, start_column, space, len(tokens)))
        column += position - start
        space = False
    tokens.append(Token("eof", None, "", line, column, space, len(tokens)))
    return tokens


class Reader:
    def __init__(self, text, column=1):
        self.tokens = tokenize(text, column)
        self.position = 0
        self.names = {}
        self.counts = {}
        sys.setrecursionlimit(max(sys.getrecursionlimit(), len(self.tokens) * 5 + 2000))

    def peek(self):
        return self.tokens[self.position]

    def take(self):
        token = self.peek()
        if token.kind != "eof":
            self.position += 1
        return token

    def punctuation(self, spelling):
        token = self.peek()
        return token.kind == "punct" and token.value == spelling

    def expect(self, spelling):
        token = self.take()
        if token.kind != "punct" or token.value != spelling:
            raise SyntaxError(token)

    def clause(self, query=False):
        self.names, self.counts = {}, {}
        term, priority = self.term(1200)
        token = self.take()
        if token.kind != "end":
            raise SyntaxError(token)
        if query and self.peek().kind != "eof":
            raise SyntaxError(self.peek())
        return term

    def term(self, limit):
        term, priority = self.primary(limit)
        while True:
            token = self.peek()
            is_operator = ((token.kind == "name" and token.value in INFIX)
                           or (token.kind == "punct" and token.value == ","))
            if not is_operator:
                return term, priority
            p, left, right = INFIX[token.value]
            if p > limit or priority > left:
                return term, priority
            self.take()
            argument, argument_priority = self.term(right)
            term, priority = Compound(token.value, term, argument), p

    def can_start(self):
        token = self.peek()
        return (token.kind in {"integer", "variable", "quoted"}
                or token.kind == "punct" and token.value in {"(", "["}
                or token.kind == "name" and (token.value not in INFIX or token.value in PREFIX))

    def primary(self, limit):
        token = self.take()
        if token.kind == "integer":
            return token.value, 0
        if token.kind == "variable":
            name = token.value
            self.counts[name] = self.counts.get(name, 0) + 1
            if name == "_":
                return Variable(), 0
            if name not in self.names:
                self.names[name] = Variable()
            return self.names[name], 0
        if token.kind == "punct" and token.value == "(":
            term, priority = self.term(1200)
            self.expect(")")
            return term, 0
        if token.kind == "punct" and token.value == "[":
            if self.punctuation("]"):
                self.take()
                return "[]", 0
            elements = [self.term(999)[0]]
            while self.punctuation(","):
                self.take()
                elements.append(self.term(999)[0])
            tail = "[]"
            if self.punctuation("|"):
                self.take()
                tail = self.term(999)[0]
            self.expect("]")
            return make_list(elements, tail), 0
        if token.kind in {"name", "quoted"}:
            if self.punctuation("(") and not self.peek().space:
                self.take()
                arguments = [self.term(999)[0]]
                while self.punctuation(","):
                    self.take()
                    arguments.append(self.term(999)[0])
                self.expect(")")
                return Compound(token.value, *arguments), 0
            if token.kind == "name" and token.value == "-" and self.peek().kind == "integer" and not self.peek().space:
                return -self.take().value, 0
            if token.kind == "name" and token.value in PREFIX and self.can_start():
                priority = PREFIX[token.value]
                if priority > limit:
                    raise SyntaxError(token, "operator priority clash")
                argument = self.term(priority)[0]
                return Compound(token.value, argument), priority
            return token.value, 0
        raise SyntaxError(token)
