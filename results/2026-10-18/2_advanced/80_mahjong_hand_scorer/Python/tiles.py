"""Tile notation, kinds, red fives and indicator cycles."""

from collections import namedtuple


Tile = namedtuple("Tile", "kind red")
SUITS = "mpsz"
WINDS = "ESWN"
WIND_TILES = {wind: 27 + index for index, wind in enumerate(WINDS)}
YAOCHUU = (0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33)
GREEN = frozenset((19, 20, 21, 23, 25, 32))


def parse(text, allow_empty=False):
    if text == "-":
        return [] if allow_empty else None
    result, digits = [], []
    for character in text:
        if "0" <= character <= "9":
            digits.append(int(character))
        elif character in SUITS and digits:
            suit = SUITS.index(character)
            for digit in digits:
                if suit == 3 and not 1 <= digit <= 7:
                    return None
                number = 5 if digit == 0 else digit
                result.append(Tile(suit * 9 + number - 1, digit == 0))
            digits = []
        else:
            return None
    return result if result and not digits else None


def name(kind):
    return str(kind % 9 + 1) + SUITS[kind // 9]


def block(kinds):
    ordered = sorted(kinds)
    return "".join(str(kind % 9 + 1) for kind in ordered) + SUITS[ordered[0] // 9]


def counts(tiles):
    result = [0] * 34
    for tile in tiles:
        result[tile.kind] += 1
    return result


def honor(kind):
    return kind >= 27


def terminal(kind):
    return kind < 27 and kind % 9 in (0, 8)


def yaochuu(kind):
    return honor(kind) or terminal(kind)


def next_dora(kind):
    if kind < 27:
        return kind // 9 * 9 + (kind % 9 + 1) % 9
    if kind < 31:
        return 27 + (kind - 26) % 4
    return 31 + (kind - 30) % 3
