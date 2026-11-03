"""LZW with code-count widths and dictionary reset at code 4096."""

from dataclasses import dataclass, field

from bitio import BitReader, BitWriter, DecodeError


CLEAR = 256
END = 257
FIRST = 258
LIMIT = 4096


@dataclass
class Statistics:
    codes: int = 0
    clears: int = 0
    widths: list[int] = field(default_factory=lambda: [0, 0, 0, 0])
    longest: int = 0


def encode(data):
    writer = BitWriter()
    statistics = Statistics()
    dictionary = {bytes((value,)): value for value in range(256)}
    next_code = FIRST
    since_clear = 0

    def emit(code, sequence_length=0):
        nonlocal since_clear
        width = min(12, (FIRST + since_clear).bit_length())
        writer.write(code, width)
        statistics.codes += 1
        statistics.widths[width - 9] += 1
        statistics.longest = max(statistics.longest, sequence_length)
        if code == CLEAR:
            statistics.clears += 1
            since_clear = 0
        else:
            since_clear += 1

    emit(CLEAR)
    sequence = b""
    for value in data:
        byte = bytes((value,))
        extended = sequence + byte
        if extended in dictionary:
            sequence = extended
            continue
        emit(dictionary[sequence], len(sequence))
        dictionary[extended] = next_code
        next_code += 1
        if next_code == LIMIT:
            emit(CLEAR)
            dictionary = {bytes((value,)): value for value in range(256)}
            next_code = FIRST
        sequence = byte
    if sequence:
        emit(dictionary[sequence], len(sequence))
    emit(END)
    return writer.finish(), statistics


def decode(payload, original_size):
    reader = BitReader(payload)
    dictionary = [bytes((value,)) for value in range(256)] + [None, None]
    previous = None
    since_clear = 0
    output = bytearray()
    while True:
        count = since_clear
        width = min(12, (FIRST + count).bit_length())
        code = reader.read(width, len(output))
        if code == CLEAR:
            dictionary = [bytes((value,)) for value in range(256)] + [None, None]
            previous = None
            since_clear = 0
            continue
        since_clear += 1
        if code == END:
            if len(output) < original_size:
                raise DecodeError("early_end", len(output))
            return bytes(output)
        if count == LIMIT - FIRST:
            raise DecodeError("bad_code", len(output))
        next_code = len(dictionary)
        if previous is None:
            if code >= 256:
                raise DecodeError("bad_code", len(output))
            sequence = dictionary[code]
        elif code < next_code:
            sequence = dictionary[code]
        elif code == next_code:
            preceding = dictionary[previous]
            sequence = preceding + preceding[:1]
        else:
            raise DecodeError("bad_code", len(output))
        if len(output) + len(sequence) > original_size:
            raise DecodeError("overrun", len(output))
        output.extend(sequence)
        if previous is not None:
            dictionary.append(dictionary[previous] + sequence[:1])
        previous = code
