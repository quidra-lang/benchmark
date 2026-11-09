from collections import namedtuple


Token = namedtuple("Token", "kind spelling position")
KEYWORDS = frozenset("int bool void true false if else while for break continue return print read".split())
PAIRS = frozenset(("<=", ">=", "==", "!=", "&&", "||"))
SYMBOLS = frozenset("+-*/%<>=!(){}[],;")


class CompileError(Exception):
    def __init__(self, kind, position, message):
        super().__init__(message)
        self.kind = kind
        self.position = position
        self.message = message


def letter(character):
    return "A" <= character <= "Z" or "a" <= character <= "z"


def digit(character):
    return "0" <= character <= "9"


def tokenize(lines):
    source = "\n".join(text for number, text in lines) + "\n"
    line, column = lines[0][0], 1
    position = 0
    tokens = []
    while position < len(source):
        character = source[position]
        start = line, column
        if character == " ":
            position += 1
            column += 1
            continue
        if character == "\n":
            position += 1
            line += 1
            column = 1
            continue
        pair = source[position:position + 2]
        if pair == "//":
            end = source.index("\n", position)
            column += end - position
            position = end
            continue
        if pair == "/*":
            end = source.find("*/", position + 2)
            if end < 0:
                raise CompileError("lexical", start, "unterminated comment")
            end += 2
            comment = source[position:end]
            newlines = comment.count("\n")
            if newlines:
                line += newlines
                column = len(comment.rsplit("\n", 1)[1]) + 1
            else:
                column += len(comment)
            position = end
            continue
        end = position + 1
        if letter(character) or character == "_":
            while end < len(source) and (letter(source[end]) or digit(source[end]) or source[end] == "_"):
                end += 1
            spelling = source[position:end]
            kind = "keyword" if spelling in KEYWORDS else "identifier"
        elif digit(character):
            while end < len(source) and digit(source[end]):
                end += 1
            spelling = source[position:end]
            if int(spelling) > 2147483647:
                raise CompileError("lexical", start, "integer literal too large")
            kind = "integer"
        elif pair in PAIRS:
            end += 1
            spelling, kind = pair, "symbol"
        elif character in SYMBOLS:
            spelling, kind = character, "symbol"
        else:
            raise CompileError("lexical", start, f"unexpected character '{character}'")
        tokens.append(Token(kind, spelling, start))
        column += end - position
        position = end
    last_number, last_text = lines[-1]
    tokens.append(Token("end", "", (last_number, len(last_text) + 1)))
    return tokens
