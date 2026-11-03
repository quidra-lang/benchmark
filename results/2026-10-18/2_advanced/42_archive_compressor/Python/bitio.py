"""Most-significant-bit-first payload I/O and positioned decoding errors."""


class DecodeError(Exception):
    def __init__(self, kind, position):
        super().__init__(f"{kind} at {position}")
        self.kind = kind
        self.position = position


class BitWriter:
    def __init__(self):
        self.data = bytearray()
        self.partial = 0
        self.used = 0
        self.bit_count = 0

    def write(self, value, width):
        for shift in range(width - 1, -1, -1):
            self.partial = (self.partial << 1) | ((value >> shift) & 1)
            self.used += 1
            if self.used == 8:
                self.data.append(self.partial)
                self.partial = 0
                self.used = 0
        self.bit_count += width

    def finish(self):
        if self.used:
            return bytes(self.data) + bytes((self.partial << (8 - self.used),))
        return bytes(self.data)


class BitReader:
    def __init__(self, payload, zero_fill=False):
        self.payload = payload
        self.position = 0
        self.limit = len(payload) * 8
        self.zero_fill = zero_fill

    def read(self, width, output_position=0):
        if not self.zero_fill and self.position + width > self.limit:
            raise DecodeError("end_of_data", output_position)
        value = 0
        for _ in range(width):
            value <<= 1
            if self.position < self.limit:
                byte = self.payload[self.position // 8]
                value |= (byte >> (7 - self.position % 8)) & 1
            self.position += 1
        return value
