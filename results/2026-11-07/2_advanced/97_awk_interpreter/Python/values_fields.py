from collections import namedtuple


Value = namedtuple("Value", "kind text numeric")
UNINITIALIZED = Value("uninitialized", None, 0)
WHITESPACE = " \t\n"


def number(value):
    return Value("number", None, value)


def string(value):
    return Value("string", value, None)


def numeric_prefix(text):
    text = text.lstrip(WHITESPACE)
    index, sign = 0, 1
    if text.startswith(("+", "-")):
        sign = -1 if text[0] == "-" else 1
        index = 1
    start = index
    while index < len(text) and "0" <= text[index] <= "9":
        index += 1
    return sign * int(text[start:index]) if index > start else 0


def input_value(text):
    trimmed = text.strip(WHITESPACE)
    digits = trimmed[1:] if trimmed.startswith(("+", "-")) else trimmed
    if digits and all("0" <= character <= "9" for character in digits):
        return Value("strnum", text, numeric_prefix(trimmed))
    return string(text)


def to_number(value):
    return numeric_prefix(value.text) if value.kind == "string" else value.numeric


def to_string(value):
    if value.kind == "number":
        return str(value.numeric)
    if value.kind == "uninitialized":
        return ""
    return value.text


def truth(value):
    return bool(value.text) if value.kind == "string" else value.numeric != 0


def compare(first, second):
    if first.kind != "string" and second.kind != "string":
        a, b = to_number(first), to_number(second)
    else:
        a, b = to_string(first), to_string(second)
    return (a > b) - (a < b)


def subscript_order(text):
    digits = text[1:] if text.startswith("-") else text
    if text == "0" or digits and "1" <= digits[0] <= "9" and all("0" <= character <= "9" for character in digits):
        return 0, int(text)
    return 1, text


def split_pieces(text, separator):
    if not text:
        return []
    if separator == "":
        return list(text)
    if separator != " ":
        return text.split(separator)
    pieces, start = [], None
    for index, character in enumerate(text):
        if character in WHITESPACE:
            if start is not None:
                pieces.append(text[start:index])
                start = None
        elif start is None:
            start = index
    if start is not None:
        pieces.append(text[start:])
    return pieces


class Record:
    def __init__(self, special):
        self.special = special
        self.zero = string("")
        self.fields = []

    def set(self, text):
        self.zero = input_value(text)
        separator = to_string(self.special("FS"))
        self.fields = [input_value(piece) for piece in split_pieces(text, separator)]

    def read(self, index):
        if index == 0:
            return self.zero
        return self.fields[index - 1] if index <= len(self.fields) else UNINITIALIZED

    def rebuild(self):
        separator = to_string(self.special("OFS"))
        self.zero = input_value(separator.join(to_string(value) for value in self.fields))

    def write(self, index, value):
        if index == 0:
            self.set(to_string(value))
            return
        if index > len(self.fields):
            self.fields.extend(string("") for _ in range(index - len(self.fields)))
        self.fields[index - 1] = value
        self.rebuild()

    def resize(self, size):
        if size < len(self.fields):
            del self.fields[size:]
        else:
            self.fields.extend(string("") for _ in range(size - len(self.fields)))
        self.rebuild()


def quoted(text):
    parts = ['"']
    escapes = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\t": "\\t"}
    for character in text:
        if character in escapes:
            parts.append(escapes[character])
        elif 32 <= ord(character) <= 126:
            parts.append(character)
        else:
            parts.append("\\" + format(ord(character), "03o"))
    parts.append('"')
    return "".join(parts)


def describe(value):
    if value.kind == "number":
        return str(value.numeric)
    if value.kind == "uninitialized":
        return "(uninitialized)"
    return quoted(value.text) + (" (strnum)" if value.kind == "strnum" else "")
