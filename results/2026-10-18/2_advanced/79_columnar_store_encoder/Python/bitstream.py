class Reader:
    def __init__(self, data, position=0):
        self.data = data
        self.position = position

    def read(self, count):
        start = self.position
        self.position += count
        return self.data[start:self.position]

    def byte(self):
        value = self.data[self.position]
        self.position += 1
        return value

    def uleb(self):
        value = shift = 0
        while True:
            byte = self.byte()
            value |= (byte & 127) << shift
            if byte < 128:
                return value
            shift += 7

    def zigzag(self):
        value = self.uleb()
        return value // 2 if value % 2 == 0 else -(value + 1) // 2

    def integer(self, signed=False):
        return int.from_bytes(self.read(4), "little", signed=signed)


def uleb(value):
    output = bytearray()
    while value >= 128:
        output.append(value % 128 + 128)
        value //= 128
    output.append(value)
    return bytes(output)


def zigzag(value):
    return uleb(2 * value if value >= 0 else -2 * value - 1)


def integer(value, signed=False):
    return value.to_bytes(4, "little", signed=signed)


def pack(values, width):
    output = bytearray()
    buffer = occupied = 0
    for value in values:
        buffer |= value << occupied
        occupied += width
        while occupied >= 8:
            output.append(buffer & 255)
            buffer >>= 8
            occupied -= 8
    return bytes(output)


def unpack(reader, width, count):
    values = []
    buffer = occupied = 0
    mask = (1 << width) - 1
    for index in range(count):
        while occupied < width:
            buffer |= reader.byte() << occupied
            occupied += 8
        values.append(buffer & mask)
        buffer >>= width
        occupied -= width
    return values


def adler32(data):
    first, second = 1, 0
    for byte in data:
        first = (first + byte) % 65521
        second = (second + first) % 65521
    return second * 65536 + first


def hybrid_encode(values, width):
    count = len(values)
    runs = [0] * count
    for index in range(count - 1, -1, -1):
        runs[index] = 1
        if index + 1 < count and values[index] == values[index + 1]:
            runs[index] += runs[index + 1]
    output = bytearray()
    index = 0
    while index < count:
        if runs[index] >= 8:
            output.extend(uleb(2 * runs[index]))
            output.extend(values[index].to_bytes((width + 7) // 8, "little"))
            index += runs[index]
        else:
            end, groups = index, 0
            while True:
                end += 8
                groups += 1
                if end >= count or groups == 63 or runs[end] >= 8:
                    break
            output.extend(uleb(2 * groups + 1))
            block = list(values[index:min(end, count)])
            block.extend([0] * (end - index - len(block)))
            output.extend(pack(block, width))
            index = end
    return bytes(output)


def hybrid_decode(reader, width, count):
    values = []
    while len(values) < count:
        header = reader.uleb()
        if header % 2 == 0:
            value = int.from_bytes(reader.read((width + 7) // 8), "little")
            values.extend([value] * (header // 2))
        else:
            groups = (header - 1) // 2
            values.extend(unpack(reader, width, groups * 8))
    return values[:count]
