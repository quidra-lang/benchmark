from line_solver import FILLED


DIGITS = "0123456789"
CLUE_LINE_CHARACTERS = DIGITS + " "
MAX_TOKEN_LENGTH = 2


def is_clue_line(text):
    return text != "" and all(character in CLUE_LINE_CHARACTERS for character in text)


def valid_token(token):
    return (
        1 <= len(token) <= MAX_TOKEN_LENGTH
        and all(character in DIGITS for character in token)
        and token[0] != "0"
    )


def parse_clue(text):
    if text == "0":
        return []
    tokens = text.split(" ")
    if not all(valid_token(token) for token in tokens):
        return None
    return [int(token) for token in tokens]


def run_clue(cells):
    clue = []
    run = 0
    for state in cells:
        if state == FILLED:
            run += 1
        elif run > 0:
            clue.append(run)
            run = 0
    if run > 0:
        clue.append(run)
    return clue


def spaced(clue):
    return " ".join(str(length) for length in clue) if clue else "0"


def comma_separated(clue):
    return ",".join(str(length) for length in clue) if clue else "0"


def span(clue):
    return sum(clue) + len(clue) - 1


def fits(clue, length):
    return span(clue) <= length
