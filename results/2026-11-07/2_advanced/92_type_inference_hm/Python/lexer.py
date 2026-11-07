KEYWORDS = set("let rec and in fun if then else match with true false mod val".split())
SYMBOLS = set(";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |".split())
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"'}


class Token:
    def __init__(self, kind, spelling, value, position):
        self.kind = kind
        self.spelling = spelling
        self.value = value
        self.position = position

    def is_name(self):
        return self.kind == "identifier" and self.spelling != "_"


def letter(character):
    return "A" <= character <= "Z" or "a" <= character <= "z"


def word_character(character):
    return letter(character) or "0" <= character <= "9" or character == "_"


def tokenize(source, filename):
    tokens = []
    index, line, column = 0, 1, 1
    while index < len(source):
        start = index
        position = filename, line, column
        character = source[index]
        kind, value = None, None
        if character in " \n":
            index += 1
        elif source.startswith("(*", index):
            closing = source.find("*)", index + 2)
            if closing < 0:
                kind, value = "invalid", "unterminated comment"
                index = len(source)
            else:
                index = closing + 2
        elif "0" <= character <= "9":
            index += 1
            while index < len(source) and "0" <= source[index] <= "9":
                index += 1
            digits = source[start:index].lstrip("0") or "0"
            if len(digits) > 10 or len(digits) == 10 and digits > "2147483647":
                kind, value = "invalid", "integer literal too large"
            else:
                kind, value = "integer", int(digits)
        elif letter(character) or character == "_":
            index += 1
            while index < len(source) and (word_character(source[index]) or source[index] == "'"):
                index += 1
            value = source[start:index]
            kind = value if value in KEYWORDS else "identifier"
        elif character == "'" and index + 1 < len(source) and "a" <= source[index + 1] <= "z":
            index += 2
            while index < len(source) and word_character(source[index]):
                index += 1
            kind, value = "type_variable", source[start:index]
        elif character == '"':
            index += 1
            decoded = []
            invalid_escape = False
            while index < len(source) and source[index] not in '"\n':
                if source[index] == "\\" and index + 1 < len(source) and source[index + 1] != "\n":
                    escape = source[index + 1]
                    if escape in ESCAPES:
                        decoded.append(ESCAPES[escape])
                    else:
                        invalid_escape = True
                    index += 2
                else:
                    decoded.append(source[index])
                    index += 1
            if index == len(source) or source[index] == "\n":
                kind, value = "invalid", "unterminated string"
            else:
                index += 1
                if invalid_escape:
                    kind, value = "invalid", "invalid escape sequence"
                else:
                    kind, value = "string", "".join(decoded)
        else:
            symbol = source[index:index + 2]
            if symbol in SYMBOLS:
                index += 2
                kind = value = symbol
            elif character in SYMBOLS:
                index += 1
                kind = value = character
            else:
                index += 1
                kind, value = "invalid", f"illegal character '{character}'"
        consumed = source[start:index]
        if kind is not None:
            tokens.append(Token(kind, consumed, value, position))
        newlines = consumed.count("\n")
        if newlines:
            line += newlines
            column = len(consumed) - consumed.rfind("\n")
        else:
            column += len(consumed)
    tokens.append(Token("EOF", "", None, (filename, source.count("\n") + 1, 1)))
    return tokens
