"""Integer arithmetic coding with an adaptive model for each prior byte."""

from dataclasses import dataclass
from itertools import chain

from bitio import BitReader, BitWriter, DecodeError


TOP = 65535
HALF = 32768
QUARTER = 16384
THREE = 49152
EOF = 256


@dataclass
class Statistics:
    bits: int
    contexts: int
    rescales: int


class FrequencyTable:
    def __init__(self):
        self.frequencies = [1] * 257
        self.total = 257
        self.rescales = 0

    def interval(self, symbol):
        return sum(self.frequencies[:symbol]), self.frequencies[symbol]

    def locate(self, value):
        cumulative = 0
        for symbol, frequency in enumerate(self.frequencies):
            if value < cumulative + frequency:
                return symbol, cumulative, frequency
            cumulative += frequency
        raise ValueError("arithmetic interval is outside the model")

    def update(self, symbol):
        self.frequencies[symbol] += 32
        self.total += 32
        if self.total >= 8192:
            self.frequencies = [(frequency + 1) // 2
                                for frequency in self.frequencies]
            self.total = sum(self.frequencies)
            self.rescales += 1


class Model:
    def __init__(self):
        self.tables = {}

    def table(self, context):
        if context not in self.tables:
            self.tables[context] = FrequencyTable()
        return self.tables[context]


def encode(data):
    writer = BitWriter()
    model = Model()
    low = 0
    high = TOP
    follow = 0
    context = 10

    def emit(bit):
        nonlocal follow
        writer.write(bit, 1)
        for _ in range(follow):
            writer.write(1 - bit, 1)
        follow = 0

    for symbol in chain(data, (EOF,)):
        table = model.table(context)
        cumulative, frequency = table.interval(symbol)
        span = high - low + 1
        high = low + span * (cumulative + frequency) // table.total - 1
        low += span * cumulative // table.total
        while True:
            if high < HALF:
                emit(0)
            elif low >= HALF:
                emit(1)
                low -= HALF
                high -= HALF
            elif low >= QUARTER and high < THREE:
                follow += 1
                low -= QUARTER
                high -= QUARTER
            else:
                break
            low *= 2
            high = high * 2 + 1
        if symbol != EOF:
            table.update(symbol)
            context = symbol
    follow += 1
    emit(0 if low < QUARTER else 1)
    statistics = Statistics(writer.bit_count, len(model.tables),
                            sum(table.rescales for table in model.tables.values()))
    return writer.finish(), statistics


def decode(payload, original_size):
    reader = BitReader(payload, zero_fill=True)
    model = Model()
    output = bytearray()
    low = 0
    high = TOP
    value = reader.read(16)
    context = 10
    while True:
        table = model.table(context)
        span = high - low + 1
        quantile = ((value - low + 1) * table.total - 1) // span
        symbol, cumulative, frequency = table.locate(quantile)
        high = low + span * (cumulative + frequency) // table.total - 1
        low += span * cumulative // table.total
        while True:
            if high < HALF:
                pass
            elif low >= HALF:
                low -= HALF
                high -= HALF
                value -= HALF
            elif low >= QUARTER and high < THREE:
                low -= QUARTER
                high -= QUARTER
                value -= QUARTER
            else:
                break
            low *= 2
            high = high * 2 + 1
            value = value * 2 + reader.read(1)
        if symbol == EOF:
            if len(output) < original_size:
                raise DecodeError("early_end", len(output))
            return bytes(output)
        if len(output) == original_size:
            raise DecodeError("overrun", len(output))
        output.append(symbol)
        table.update(symbol)
        context = symbol
