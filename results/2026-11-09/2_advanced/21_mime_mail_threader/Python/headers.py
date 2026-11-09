import string

from mime import strict_base64


WHITESPACE = " \t"
ADDRESS_SPECIALS = "<>:;@,."
ADDRESS_WORD_CHARS = string.ascii_letters + string.digits + "!#$%&'*+-/=?^_`{|}~"
MIME_SPECIALS = "/;="
MIME_EXCLUDED = "()<>@,;:\\\"/[]?="
MIME_WORD_CHARS = "".join(chr(code) for code in range(33, 127) if chr(code) not in MIME_EXCLUDED)


class Header:
    def __init__(self):
        self.fields = []
        self.invalid_lines = []

    def value(self, name):
        name = name.lower()
        for field_name, value in self.fields:
            if field_name == name:
                return value
        return None

    def count(self, name):
        name = name.lower()
        return sum(1 for field_name, _ in self.fields if field_name == name)


class Token:
    def __init__(self, kind, text, spaced):
        self.kind = kind
        self.text = text
        self.spaced = spaced


def split_words(text):
    return [word for word in text.replace("\t", " ").split(" ") if word]


def collapse_whitespace(text):
    return " ".join(split_words(text))


def is_field_name(name):
    return name != "" and all(33 <= ord(char) <= 126 for char in name)


def parse_fields(lines):
    header = Header()
    names = []
    values = []
    in_field = False
    for number, text in lines:
        if text[0] in WHITESPACE:
            if in_field:
                values[-1] += text
            else:
                header.invalid_lines.append(number)
            continue
        name, colon, value = text.partition(":")
        in_field = colon != "" and is_field_name(name)
        if in_field:
            names.append(name.lower())
            values.append(value)
        else:
            header.invalid_lines.append(number)
    header.fields = [(name, value.strip(WHITESPACE)) for name, value in zip(names, values)]
    return header


def remove_comments(text):
    result = []
    depth = 0
    escaped = False
    for char in text:
        if depth == 0:
            if char == "(":
                depth = 1
                result.append(" ")
            else:
                result.append(char)
        elif escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
    if depth != 0:
        return None
    return "".join(result)


def skip_comment(text, position):
    depth = 0
    while position < len(text):
        char = text[position]
        if char == "\\":
            position += 2
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return position + 1
        position += 1
    return None


def read_quoted(text, position):
    chars = []
    position += 1
    while position < len(text):
        char = text[position]
        if char == '"':
            return "".join(chars), position + 1
        if char == "\\":
            position += 1
            if position == len(text):
                return None
            char = text[position]
        chars.append(char)
        position += 1
    return None


def tokenize(text, specials, word_chars):
    tokens = []
    position = 0
    spaced = False
    while position < len(text):
        char = text[position]
        if char in WHITESPACE:
            spaced = True
            position += 1
            continue
        if char == "(":
            position = skip_comment(text, position)
            if position is None:
                return None
            spaced = True
            continue
        if char == '"':
            quoted = read_quoted(text, position)
            if quoted is None:
                return None
            value, position = quoted
            tokens.append(Token("quoted", value, spaced))
        elif char in specials:
            tokens.append(Token(char, char, spaced))
            position += 1
        elif char in word_chars:
            end = position
            while end < len(text) and text[end] in word_chars:
                end += 1
            tokens.append(Token("word", text[position:end], spaced))
            position = end
        else:
            return None
        spaced = False
    return tokens


def tokenize_address(text):
    return tokenize(text, ADDRESS_SPECIALS, ADDRESS_WORD_CHARS)


def tokenize_mime(text):
    return tokenize(text, MIME_SPECIALS, MIME_WORD_CHARS)


def decode_q(text):
    result = bytearray()
    position = 0
    while position < len(text):
        char = text[position]
        if char == "_":
            result.append(32)
            position += 1
        elif char == "=":
            digits = text[position + 1:position + 3]
            if len(digits) != 2 or not all(digit in string.hexdigits for digit in digits):
                return None
            result.append(int(digits, 16))
            position += 3
        else:
            result.append(ord(char))
            position += 1
    return bytes(result)


def encoded_word_parts(word):
    if len(word) < 4 or not word.startswith("=?") or not word.endswith("?="):
        return None
    pieces = word[2:-2].split("?")
    if len(pieces) != 3 or "" in pieces:
        return None
    return pieces


def decode_encoded_text(charset, encoding, encoded):
    if charset.lower() != "us-ascii":
        return None
    if encoding in ("Q", "q"):
        data = decode_q(encoded)
    elif encoding in ("B", "b"):
        data = strict_base64(encoded)
    else:
        return None
    if data is None or not all(32 <= byte <= 126 for byte in data):
        return None
    return data.decode("ascii")


def decode_word(word):
    pieces = encoded_word_parts(word)
    if pieces is None:
        return word, False, False
    decoded = decode_encoded_text(*pieces)
    if decoded is None:
        return word, False, True
    return decoded, True, False


def decode_unstructured(value):
    parts = []
    error = False
    previous_decoded = False
    for word in split_words(value):
        text, decoded, failed = decode_word(word)
        if parts and not (decoded and previous_decoded):
            parts.append(" ")
        parts.append(text)
        previous_decoded = decoded
        error = error or failed
    return collapse_whitespace("".join(parts)), error


def parse_parameters(value, with_subtype):
    tokens = tokenize_mime(value)
    if not tokens or tokens[0].kind != "word":
        return None
    main_type = tokens[0].text.lower()
    subtype = ""
    position = 1
    if with_subtype:
        if len(tokens) < 3 or tokens[1].kind != "/" or tokens[2].kind != "word":
            return None
        subtype = tokens[2].text.lower()
        position = 3
    parameters = {}
    while position < len(tokens):
        kinds = [token.kind for token in tokens[position:position + 4]]
        if len(kinds) < 4 or kinds[:3] != [";", "word", "="] or kinds[3] not in ("word", "quoted"):
            return None
        name = tokens[position + 1].text.lower()
        if name not in parameters:
            parameters[name] = tokens[position + 3].text
        position += 4
    return main_type, subtype, parameters
