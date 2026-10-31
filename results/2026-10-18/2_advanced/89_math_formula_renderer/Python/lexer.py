"""TeX-like tokens, symbol commands and lexical error locations."""

from collections import namedtuple


Token = namedtuple("Token", "kind value column")
GREEK = frozenset(
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma "
    "tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega".split()
)
FUNCTIONS = ("sin", "cos", "tan", "log", "ln", "exp", "det", "lim", "max", "min")
LARGE_OPERATORS = ("sum", "prod", "int")
SYMBOL_COMMANDS = {"\\" + name: (name, "ordinary") for name in GREEK}
SYMBOL_COMMANDS.update({"\\" + name: (name, "operator") for name in FUNCTIONS + LARGE_OPERATORS})
SYMBOL_COMMANDS.update({
    r"\cdot": ("*", "binary"), r"\times": ("x", "binary"),
    r"\pm": ("+-", "binary"), r"\mp": ("-+", "binary"),
    r"\leq": ("<=", "relation"), r"\geq": (">=", "relation"),
    r"\neq": ("!=", "relation"), r"\approx": ("~=", "relation"),
    r"\to": ("->", "relation"), r"\infty": ("oo", "ordinary"),
    r"\ldots": ("...", "ordinary"), r"\cdots": ("...", "ordinary"),
    r"\quad": ("  ", "ordinary"), r"\,": (" ", "ordinary"),
    r"\{": ("{", "open"), r"\}": ("}", "close"),
})
COMMAND_NAMES = frozenset(value[1:] for value in SYMBOL_COMMANDS if value[1:].isalpha())
ACCENTS = frozenset(("overline", "hat", "vec", "dot", "tilde", "overbrace", "underbrace"))
CONSTRUCTS = frozenset(("frac", "binom", "overset", "underset", "sqrt", "left", "right"))
RAW_COMMANDS = frozenset(("text", "begin", "end", "tag", "label", "eqref"))
ENVIRONMENTS = frozenset(("matrix", "pmatrix", "bmatrix", "vmatrix", "cases"))
SYMBOLS = frozenset("+-*/=<>:()[],;.!|'")


class FormulaError(Exception):
    def __init__(self, column, message):
        super().__init__(message)
        self.column = column
        self.message = message


def letter(character):
    return "A" <= character <= "Z" or "a" <= character <= "z"


def digit(character):
    return "0" <= character <= "9"


def tokenize(line):
    tokens = []
    position, length = 0, len(line)
    while position < length:
        character = line[position]
        column = position + 1
        if character == " ":
            position += 1
            continue
        if letter(character):
            end = position + 1
            while end < length and letter(line[end]):
                end += 1
            tokens.append(Token("identifier", line[position:end], column))
            position = end
            continue
        if digit(character):
            end = position + 1
            while end < length and digit(line[end]):
                end += 1
            if end + 1 < length and line[end] == "." and digit(line[end + 1]):
                end += 2
                while end < length and digit(line[end]):
                    end += 1
            tokens.append(Token("number", line[position:end], column))
            position = end
            continue
        if character in SYMBOLS or character in "{}^_&":
            kind = "symbol" if character in SYMBOLS else character
            tokens.append(Token(kind, character, column))
            position += 1
            continue
        if character != "\\":
            raise FormulaError(column, "invalid character " + character)
        position += 1
        if position < length and line[position] in "\\{},":
            escaped = line[position]
            kind = "newline" if escaped == "\\" else "command"
            tokens.append(Token(kind, "\\" + escaped, column))
            position += 1
            continue
        start = position
        while position < length and letter(line[position]):
            position += 1
        name = line[start:position]
        if not name:
            raise FormulaError(column, "invalid command")
        if name in RAW_COMMANDS:
            while position < length and line[position] == " ":
                position += 1
            if position == length or line[position] != "{":
                raise FormulaError(position + 1, "expected {")
            end = line.find("}", position + 1)
            if end == -1:
                raise FormulaError(column, "unterminated argument")
            argument = line[position + 1:end]
            if name in ("begin", "end") and argument not in ENVIRONMENTS:
                raise FormulaError(column, f'unknown environment "{argument}"')
            tokens.append(Token(name, argument, column))
            position = end + 1
        elif "\\" + name in SYMBOL_COMMANDS:
            tokens.append(Token("command", "\\" + name, column))
        elif name in ACCENTS:
            tokens.append(Token("accent", name, column))
        elif name in CONSTRUCTS:
            tokens.append(Token(name, name, column))
        else:
            raise FormulaError(column, "unknown command \\" + name)
    tokens.append(Token("eof", "", length + 1))
    return tokens
