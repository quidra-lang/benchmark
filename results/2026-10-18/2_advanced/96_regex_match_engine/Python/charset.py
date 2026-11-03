"""ASCII character classes, case matching and positional assertions."""


ASCII = frozenset(range(128))
DIGITS = frozenset(range(ord("0"), ord("9") + 1))
LOWER = frozenset(range(ord("a"), ord("z") + 1))
UPPER = frozenset(range(ord("A"), ord("Z") + 1))
WORD = DIGITS | LOWER | UPPER | {ord("_")}
SPACE = frozenset((9, 10, 11, 12, 13, 32))
STANDARD = {"d": DIGITS, "w": WORD, "s": SPACE}


def is_letter(character):
    code = ord(character)
    return code in LOWER or code in UPPER


def switched(character):
    return character.upper() if character in "abcdefghijklmnopqrstuvwxyz" else (
        character.lower() if character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" else character
    )


def escaped_set(letter):
    code = letter.lower()
    result = STANDARD[code]
    return ASCII - result if letter.isupper() else result


def equal(a, b, flags):
    return a == b or (
        "i" in flags and is_letter(a) and switched(a) == b
    )


def test_char(text, pos, expected, flags):
    return pos < len(text) and equal(text[pos], expected, flags)


def test_any(text, pos, flags):
    return pos < len(text) and ("s" in flags or text[pos] != "\n")


def test_class(text, pos, charset, negate, flags):
    if pos >= len(text):
        return False
    code = ord(text[pos])
    present = code in charset or (
        "i" in flags and is_letter(text[pos])
        and ord(switched(text[pos])) in charset
    )
    return present != negate


def is_word_at(text, pos):
    return 0 <= pos < len(text) and ord(text[pos]) in WORD


def assertion(kind, text, pos, flags):
    if kind == "BOL":
        return pos == 0 or ("m" in flags and text[pos - 1] == "\n")
    if kind == "EOL":
        return pos == len(text) or (
            "m" in flags and text[pos] == "\n"
        )
    edge = is_word_at(text, pos - 1) != is_word_at(text, pos)
    return edge if kind == "WORD" else not edge
