"""Entropy bits, stuffing, padding, restart markers, and resynchronization."""


class DecodeError(Exception):
    def __init__(self, kind):
        super().__init__(kind)
        self.kind = kind


class BitWriter:
    def __init__(self):
        self.data = bytearray()
        self.buffer = 0
        self.pending = 0
        self.padding_bits = 0
        self.stuffed_bytes = 0

    def write(self, value, width):
        for shift in range(width - 1, -1, -1):
            self.buffer = 2 * self.buffer + ((value >> shift) & 1)
            self.pending += 1
            if self.pending == 8:
                self.data.append(self.buffer)
                if self.buffer == 0xFF:
                    self.data.append(0)
                    self.stuffed_bytes += 1
                self.buffer = self.pending = 0

    def pad(self):
        if self.pending:
            width = 8 - self.pending
            self.padding_bits += width
            self.write((1 << width) - 1, width)

    def restart(self, number):
        self.pad()
        self.data.extend((0xFF, 0xD0 + number % 8))


class BitReader:
    def __init__(self, data, position):
        self.data = data
        self.position = position
        self.buffer = 0
        self.remaining = 0

    def bit(self):
        if self.remaining == 0:
            value = self.data[self.position]
            if value == 0xFF:
                if self.data[self.position + 1] != 0:
                    raise DecodeError("marker")
                self.position += 2
            else:
                self.position += 1
            self.buffer = value
            self.remaining = 8
        self.remaining -= 1
        return (self.buffer >> self.remaining) & 1

    def read(self, width):
        value = 0
        for _ in range(width):
            value = 2 * value + self.bit()
        return value

    def discard(self):
        self.buffer = self.remaining = 0


def find_resync(data, position):
    for offset in range(position, len(data) - 1):
        if data[offset] == 0xFF and (0xD0 <= data[offset + 1] <= 0xD7 or data[offset + 1] == 0xD9):
            return offset
