from collections import namedtuple


Token = namedtuple("Token", "kind spelling value position")
KEYWORDS = frozenset("BEGIN END function if else while for do break continue next exit return delete in getline print printf".split())
BUILTINS = frozenset("length substr index split sprintf toupper tolower close int".split())
PAIRS = frozenset(("+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>"))
SYMBOLS = frozenset("+-*/%^!><?:=()[]{},;$")
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "/": "/"}


class SyntaxIssue(Exception):
    def __init__(self, position):
        super().__init__(position)
        self.position = position


def letter(character):
    return "a" <= character <= "z" or "A" <= character <= "Z" or character == "_"


def digit(character):
    return "0" <= character <= "9"


def tokenize(source):
    tokens = []
    index, line, column = 0, 1, 1
    while index < len(source):
        character = source[index]
        start = line, column
        if character == " ":
            index += 1
            column += 1
            continue
        if source.startswith("\\\n", index):
            index += 2
            line += 1
            column = 1
            continue
        if character == "#":
            end = source.find("\n", index)
            if end < 0:
                end = len(source)
            column += end - index
            index = end
            continue
        if character == "\n":
            tokens.append(Token("newline", "\n", None, start))
            index += 1
            line += 1
            column = 1
            continue
        end = index + 1
        value = None
        if digit(character):
            while end < len(source) and digit(source[end]):
                end += 1
            kind, value = "number", int(source[index:end])
        elif letter(character):
            while end < len(source) and (letter(source[end]) or digit(source[end])):
                end += 1
            word = source[index:end]
            if word in KEYWORDS:
                kind = "keyword"
            elif word in BUILTINS:
                kind = "builtin"
            else:
                kind = "function_name" if end < len(source) and source[end] == "(" else "name"
        elif character == '"':
            pieces = []
            while end < len(source) and source[end] != '"':
                if source[end] == "\n":
                    raise SyntaxIssue(start)
                if source[end] == "\\":
                    if end + 1 == len(source) or source[end + 1] not in ESCAPES:
                        raise SyntaxIssue((line, column + end - index))
                    pieces.append(ESCAPES[source[end + 1]])
                    end += 2
                else:
                    pieces.append(source[end])
                    end += 1
            if end == len(source):
                raise SyntaxIssue(start)
            end += 1
            kind, value = "string", "".join(pieces)
        elif source[index:index + 2] in PAIRS:
            end += 1
            kind = "symbol"
        elif character in SYMBOLS:
            kind = "symbol"
        else:
            raise SyntaxIssue(start)
        tokens.append(Token(kind, source[index:end], value, start))
        column += end - index
        index = end
    tokens.append(Token("end", "", None, (source.count("\n") + 1, 1)))
    return tokens
