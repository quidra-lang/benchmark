from bitstream import Reader, hybrid_decode, hybrid_encode, integer, pack, uleb, unpack, zigzag


METHODS = ("PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY")
CANDIDATES = {"INT": (0, 1, 3), "DATE": (0, 1, 3), "STRING": (0, 1, 4), "BOOL": (0, 2)}


def delta_encode(values):
    output = bytearray(uleb(128) + uleb(4) + uleb(len(values)))
    output.extend(zigzag(values[0] if values else 0))
    deltas = [values[index] - values[index - 1] for index in range(1, len(values))]
    for start in range(0, len(deltas), 128):
        block = deltas[start:start + 128]
        minimum = min(block)
        output.extend(zigzag(minimum))
        miniblocks = [[value - minimum for value in block[index:index + 32]]
                      for index in range(0, 128, 32)]
        widths = [max(miniblock, default=0).bit_length() for miniblock in miniblocks]
        output.extend(widths)
        for miniblock, width in zip(miniblocks, widths):
            if miniblock:
                output.extend(pack(miniblock + [0] * (32 - len(miniblock)), width))
    return bytes(output)


def delta_decode(reader):
    block_size = reader.uleb()
    miniblock_count = reader.uleb()
    count = reader.uleb()
    first = reader.zigzag()
    values = [first] if count else []
    miniblock_size = block_size // miniblock_count
    while len(values) < count:
        minimum = reader.zigzag()
        widths = [reader.byte() for index in range(miniblock_count)]
        for width in widths:
            if len(values) == count:
                break
            differences = unpack(reader, width, miniblock_size)
            for difference in differences[:min(miniblock_size, count - len(values))]:
                values.append(values[-1] + minimum + difference)
    return values


def encode_values(kind, method, values, dictionary=None):
    if method == 0:
        if kind in ("INT", "DATE"):
            return b"".join(integer(value, signed=True) for value in values)
        if kind == "STRING":
            return b"".join(integer(len(value)) + value.encode("ascii") for value in values)
        padded = list(values) + [0] * ((-len(values)) % 8)
        return pack(padded, 1)
    if method == 1:
        ranks = {value: index for index, value in enumerate(dictionary)}
        width = (len(dictionary) - 1).bit_length()
        return bytes([width]) + hybrid_encode([ranks[value] for value in values], width)
    if method == 2:
        encoded = hybrid_encode(values, 1)
        return integer(len(encoded)) + encoded
    if method == 3:
        return delta_encode(values)
    lengths = delta_encode([len(value) for value in values])
    return lengths + b"".join(value.encode("ascii") for value in values)


def decode_values(reader, kind, method, count, dictionary=None):
    if method == 0:
        if kind in ("INT", "DATE"):
            return [reader.integer(signed=True) for index in range(count)]
        if kind == "STRING":
            return [reader.read(reader.integer()).decode("ascii") for index in range(count)]
        return [bool(value) for value in unpack(reader, 1, (count + 7) // 8 * 8)[:count]]
    if method == 1:
        width = reader.byte()
        return [dictionary[index] for index in hybrid_decode(reader, width, count)]
    if method == 2:
        encoded = Reader(reader.read(reader.integer()))
        return [bool(value) for value in hybrid_decode(encoded, 1, count)]
    if method == 3:
        return delta_decode(reader)
    lengths = delta_decode(reader)
    return [reader.read(length).decode("ascii") for length in lengths]


def encode_statistics(kind, statistics):
    if statistics is None:
        return b"\x00"
    output = bytearray([1])
    for value in statistics:
        if kind in ("INT", "DATE"):
            output.extend(zigzag(value))
        elif kind == "STRING":
            output.extend(uleb(len(value)))
            output.extend(value.encode("ascii"))
        else:
            output.append(int(value))
    return bytes(output)


def decode_statistics(reader, kind):
    if reader.byte() == 0:
        return None
    values = []
    for index in range(2):
        if kind in ("INT", "DATE"):
            values.append(reader.zigzag())
        elif kind == "STRING":
            values.append(reader.read(reader.uleb()).decode("ascii"))
        else:
            values.append(bool(reader.byte()))
    return tuple(values)
