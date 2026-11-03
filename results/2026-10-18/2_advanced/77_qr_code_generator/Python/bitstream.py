"""MSB-first bit strings and the QR alphanumeric alphabet."""

ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
ALPHANUMERIC_VALUES = {character: index for index, character in enumerate(ALPHANUMERIC)}


class BitWriter:
    def __init__(self):
        self.parts = []
        self.length = 0

    def write(self, value, width):
        self.parts.append(f"{value:0{width}b}")
        self.length += width

    def value(self):
        return "".join(self.parts)


class BitReader:
    def __init__(self, bits):
        self.bits = bits
        self.position = 0

    def remaining(self):
        return len(self.bits) - self.position

    def read(self, width):
        start = self.position
        self.position += width
        return int(self.bits[start:self.position], 2)


def from_codewords(codewords):
    return "".join(f"{value:08b}" for value in codewords)


def to_codewords(bits):
    return [int(bits[index:index + 8], 2) for index in range(0, len(bits), 8)]


def hexadecimal(codewords):
    return "".join(f"{value:02x}" for value in codewords)
