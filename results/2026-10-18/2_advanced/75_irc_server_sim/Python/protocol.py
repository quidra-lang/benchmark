FOLD_TABLE = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ[]\\^", "abcdefghijklmnopqrstuvwxyz{}|~")
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
SPECIAL = "[]\\`_^{}|"


def fold(value):
    return value.translate(FOLD_TABLE)


def digits(value):
    return bool(value) and all("0" <= character <= "9" for character in value)


def valid_nickname(value):
    return (bool(value) and value[0] in LETTERS + SPECIAL
            and all(character in LETTERS + SPECIAL + "0123456789-" for character in value[1:]))


def valid_channel(value, maximum):
    return 2 <= len(value) <= maximum and value.startswith("#") and ":" not in value


def parse(raw):
    position = 0
    if raw.startswith(":"):
        position = raw.find(" ")
        if position == -1:
            return "", []
    while position < len(raw) and raw[position] == " ":
        position += 1
    start = position
    while position < len(raw) and raw[position] != " ":
        position += 1
    command = raw[start:position].upper()
    parameters = []
    while position < len(raw):
        while position < len(raw) and raw[position] == " ":
            position += 1
        if position == len(raw):
            break
        if raw[position] == ":":
            parameters.append(raw[position + 1:])
            break
        if len(parameters) == 14:
            parameters.append(raw[position:])
            break
        start = position
        while position < len(raw) and raw[position] != " ":
            position += 1
        parameters.append(raw[start:position])
    return command, parameters
