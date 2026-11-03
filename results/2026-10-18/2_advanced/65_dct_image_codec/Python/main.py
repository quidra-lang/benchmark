"""Integer JPEG encoding, damaged-stream decoding, and codec experiments."""

from bisect import bisect_right
from collections import namedtuple
from math import gcd, log10
from pathlib import Path
from types import SimpleNamespace

import color
import dct
from bitstream import BitReader, BitWriter, DecodeError, find_resync
from entropy import (
    HuffmanTable, TABLE_KEYS, TABLE_NAMES, amplitude, extra_bits, optimized_table,
)
from image_io import read_hex, read_params, read_ppm, read_tables, write_hex, write_ppm


Component = namedtuple("Component", "identifier h v tq td ta")
Block = namedtuple("Block", "mcu component bx by")
Symbol = namedtuple("Symbol", "table value extra width")
COMPONENT_NAMES = ("Y", "Cb", "Cr")


def standard_components(horizontal, vertical):
    return [Component(1, horizontal, vertical, 0, 0, 0),
            Component(2, 1, 1, 1, 1, 1), Component(3, 1, 1, 1, 1, 1)]


class Layout:
    def __init__(self, width, height, components, restart_interval):
        self.width, self.height = width, height
        self.components = components
        self.restart_interval = restart_interval
        self.factors = [(component.h, component.v) for component in components]
        self.hmax = max(component.h for component in components)
        self.vmax = max(component.v for component in components)
        self.mx = (width + 8 * self.hmax - 1) // (8 * self.hmax)
        self.my = (height + 8 * self.vmax - 1) // (8 * self.vmax)
        self.mcus = self.mx * self.my
        self.blocks_per_mcu = sum(component.h * component.v for component in components)
        self.blocks = []
        for mcu in range(self.mcus):
            for index, component in enumerate(components):
                for vertical in range(component.v):
                    for horizontal in range(component.h):
                        bx = component.h * (mcu % self.mx) + horizontal
                        by = component.v * (mcu // self.mx) + vertical
                        self.blocks.append(Block(mcu, index, bx, by))
        step = restart_interval or self.mcus
        self.intervals = [(first, min(step, self.mcus - first))
                          for first in range(0, self.mcus, step)]

    def interval_blocks(self, interval):
        first, count = self.intervals[interval]
        return range(first * self.blocks_per_mcu, (first + count) * self.blocks_per_mcu)


def word(value):
    return bytes((value // 256, value % 256))


def read_word(data, offset):
    return 256 * data[offset] + data[offset + 1]


def segment(marker, contents):
    return bytes((0xFF, marker)) + word(len(contents) + 2) + bytes(contents)


def read_symbol(reader, table):
    code = 0
    for length in range(1, 17):
        code = 2 * code + reader.bit()
        if (length, code) in table.decode:
            return table.decode[length, code]
    raise DecodeError("code")


def decode_block(reader, component_index, component, tables, predictors):
    coefficients = [0] * 64
    size = read_symbol(reader, tables[0, component.td])
    difference = amplitude(reader.read(size), size)
    predictors[component_index] += difference
    coefficients[0] = predictors[component_index]
    index = 1
    while index <= 63:
        symbol = read_symbol(reader, tables[1, component.ta])
        if symbol == 0:
            break
        run, size = divmod(symbol, 16)
        index += run
        if index > 63:
            raise DecodeError("index")
        if size > 0:
            coefficients[index] = amplitude(reader.read(size), size)
        index += 1
    return coefficients


class Codec:
    def __init__(self, transform, basic_quantization, standard_tables):
        self.transform = transform
        self.basic_quantization = basic_quantization
        self.standard_tables = standard_tables

    def prepare(self, image, quality, sampling, restart_interval):
        horizontal, vertical = {"444": (1, 1), "422": (2, 1), "420": (2, 2)}[sampling]
        layout = Layout(len(image[0]), len(image), standard_components(horizontal, vertical), restart_interval)
        planes = color.component_planes(color.split_planes(image), layout.factors, layout.mx, layout.my)
        quantization = dct.quantization_tables(self.basic_quantization, quality)
        coefficients = []
        for block in layout.blocks:
            plane = planes[block.component]
            pixels = [row[8 * block.bx:8 * block.bx + 8]
                      for row in plane[8 * block.by:8 * block.by + 8]]
            transformed = dct.forward(pixels, self.transform)
            table = quantization[layout.components[block.component].tq]
            coefficients.append(dct.zigzag(dct.quantize(transformed, table)))
        return SimpleNamespace(layout=layout, planes=planes, quantization=quantization,
                               coefficients=coefficients)

    def build_symbols(self, prepared):
        layout = prepared.layout
        frequencies = {key: [0] * 256 for key in TABLE_KEYS}
        blocks, differences = [], []
        for interval in range(len(layout.intervals)):
            predictors = [0, 0, 0]
            for number in layout.interval_blocks(interval):
                block = layout.blocks[number]
                component = layout.components[block.component]
                sequence = prepared.coefficients[number]
                difference = sequence[0] - predictors[block.component]
                predictors[block.component] = sequence[0]
                differences.append(difference)
                bits, size = extra_bits(difference)
                symbols = [Symbol((0, component.td), size, bits, size)]
                ac_table = (1, component.ta)
                run = 0
                for value in sequence[1:]:
                    if value == 0:
                        run += 1
                        continue
                    while run >= 16:
                        symbols.append(Symbol(ac_table, 0xF0, 0, 0))
                        run -= 16
                    bits, size = extra_bits(value)
                    symbols.append(Symbol(ac_table, 16 * run + size, bits, size))
                    run = 0
                if run > 0:
                    symbols.append(Symbol(ac_table, 0, 0, 0))
                for symbol in symbols:
                    frequencies[symbol.table][symbol.value] += 1
                blocks.append(symbols)
        return blocks, differences, frequencies

    def header(self, layout, quantization, tables):
        header = bytearray((0xFF, 0xD8))
        contents = bytearray()
        for identifier in range(2):
            contents.append(identifier)
            contents.extend(dct.zigzag(quantization[identifier]))
        header.extend(segment(0xDB, contents))
        contents = bytearray((8,))
        contents.extend(word(layout.height))
        contents.extend(word(layout.width))
        contents.append(3)
        for component in layout.components:
            contents.extend((component.identifier, 16 * component.h + component.v, component.tq))
        header.extend(segment(0xC0, contents))
        contents = bytearray()
        for table_class, identifier in TABLE_KEYS:
            table = tables[table_class, identifier]
            contents.append(16 * table_class + identifier)
            contents.extend(table.counts)
            contents.extend(table.symbols)
        header.extend(segment(0xC4, contents))
        if layout.restart_interval > 0:
            header.extend(segment(0xDD, word(layout.restart_interval)))
        contents = bytearray((3,))
        for component in layout.components:
            contents.extend((component.identifier, 16 * component.td + component.ta))
        contents.extend((0, 63, 0))
        header.extend(segment(0xDA, contents))
        return bytes(header)

    def encode_prepared(self, prepared, mode):
        symbols, differences, frequencies = self.build_symbols(prepared)
        tables = self.standard_tables if mode == "standard" else {
            key: optimized_table(frequencies[key]) for key in TABLE_KEYS
        }
        header = self.header(prepared.layout, prepared.quantization, tables)
        writer = BitWriter()
        block_bits = [0] * len(prepared.coefficients)
        intervals = []
        for interval, (first, count) in enumerate(prepared.layout.intervals):
            if interval > 0:
                writer.restart(interval - 1)
            start = len(writer.data)
            for number in prepared.layout.interval_blocks(interval):
                for symbol in symbols[number]:
                    length, code = tables[symbol.table].codes[symbol.value]
                    writer.write(code, length)
                    writer.write(symbol.extra, symbol.width)
                    block_bits[number] += length + symbol.width
            writer.pad()
            intervals.append((first, count, len(header) + start, len(writer.data) - start))
        data = header + bytes(writer.data) + bytes((0xFF, 0xD9))
        return SimpleNamespace(
            layout=prepared.layout, planes=prepared.planes, quantization=prepared.quantization,
            coefficients=prepared.coefficients, tables=tables, frequencies=frequencies,
            differences=differences, block_bits=block_bits, intervals=intervals, data=data,
            header_bytes=len(header), scan_bytes=len(writer.data),
            padding_bits=writer.padding_bits, stuffed_bytes=writer.stuffed_bytes,
        )

    def encode(self, image, quality, sampling, mode, restart_interval):
        return self.encode_prepared(self.prepare(image, quality, sampling, restart_interval), mode)

    def parse_header(self, data):
        position = 2
        segments = [(0, "SOI", 0)]
        quantization, tables = {}, {}
        restart_interval = 0
        names = {0xC0: "SOF0", 0xC4: "DHT", 0xDB: "DQT", 0xDD: "DRI", 0xDA: "SOS", 0xFE: "COM"}
        while True:
            marker = data[position + 1]
            length = read_word(data, position + 2)
            contents = data[position + 4:position + length + 2]
            name = f"APP{marker - 0xE0}" if 0xE0 <= marker <= 0xEF else names[marker]
            segments.append((position, name, length))
            position += length + 2
            if marker == 0xDB:
                for offset in range(0, len(contents), 65):
                    quantization[contents[offset]] = dct.unzigzag(contents[offset + 1:offset + 65])
            elif marker == 0xC4:
                offset = 0
                while offset < len(contents):
                    table_class, identifier = divmod(contents[offset], 16)
                    counts = list(contents[offset + 1:offset + 17])
                    symbol_count = sum(counts)
                    symbols = contents[offset + 17:offset + 17 + symbol_count]
                    tables[table_class, identifier] = HuffmanTable(counts, symbols)
                    offset += 17 + symbol_count
            elif marker == 0xC0:
                height, width = read_word(contents, 1), read_word(contents, 3)
                components = []
                for index in range(3):
                    offset = 6 + 3 * index
                    horizontal, vertical = divmod(contents[offset + 1], 16)
                    components.append(Component(contents[offset], horizontal, vertical,
                                                contents[offset + 2], 0, 0))
            elif marker == 0xDD:
                restart_interval = read_word(contents, 0)
            elif marker == 0xDA:
                for index in range(3):
                    dc_table, ac_table = divmod(contents[2 + 2 * index], 16)
                    components[index] = components[index]._replace(td=dc_table, ta=ac_table)
                break
        segments.append((len(data) - 2, "EOI", 0))
        return SimpleNamespace(
            layout=Layout(width, height, components, restart_interval), quantization=quantization,
            tables=tables, segments=segments, scan_start=position, scan_bytes=len(data) - 2 - position,
        )

    def decode_intervals(self, data, parsed):
        layout = parsed.layout
        coefficients = [[0] * 64 for _ in layout.blocks]
        states = [{"state": "lost"} for _ in layout.intervals]
        reader = BitReader(data, parsed.scan_start)
        interval = 0
        while interval < len(layout.intervals):
            predictors = [0, 0, 0]
            pending = []
            current_mcu = layout.intervals[interval][0]
            try:
                for number in layout.interval_blocks(interval):
                    block = layout.blocks[number]
                    current_mcu = block.mcu
                    component = layout.components[block.component]
                    pending.append(decode_block(reader, block.component, component, parsed.tables, predictors))
                reader.discard()
                expected = 0xD0 + interval % 8 if interval < len(layout.intervals) - 1 else 0xD9
                if data[reader.position] != 0xFF or data[reader.position + 1] != expected:
                    raise DecodeError("sync")
                for number, sequence in zip(layout.interval_blocks(interval), pending):
                    coefficients[number] = sequence
                states[interval] = {"state": "ok"}
                reader.position += 2
                interval += 1
            except DecodeError as error:
                offset = reader.position
                reader.discard()
                resync = find_resync(data, offset)
                states[interval] = {"state": "damaged", "kind": error.kind, "mcu": current_mcu,
                                    "offset": offset, "resync": resync}
                marker = data[resync + 1]
                if marker == 0xD9:
                    break
                interval = interval + 1 + ((marker - 0xD0 - interval) % 8)
                reader.position = resync + 2
        return coefficients, states

    def reconstruct_component(self, layout, component_index, coefficients, quantization, keep=64):
        component = layout.components[component_index]
        width, height = 8 * component.h * layout.mx, 8 * component.v * layout.my
        plane = [[128] * width for _ in range(height)]
        table = quantization[component.tq]
        for block, sequence in zip(layout.blocks, coefficients):
            if block.component != component_index:
                continue
            pixels = dct.inverse(dct.dequantize(sequence, table, keep), self.transform)
            for y, row in enumerate(pixels):
                plane[8 * block.by + y][8 * block.bx:8 * block.bx + 8] = row
        return plane

    def decode(self, data):
        parsed = self.parse_header(data)
        coefficients, states = self.decode_intervals(data, parsed)
        planes = [self.reconstruct_component(parsed.layout, index, coefficients, parsed.quantization)
                  for index in range(3)]
        expanded = color.upsample(planes, parsed.layout.factors, parsed.layout.width, parsed.layout.height)
        parsed.coefficients, parsed.states = coefficients, states
        parsed.planes, parsed.expanded = planes, expanded
        parsed.image = color.combine_rgb(expanded)
        return parsed

    def repair(self, decoded):
        source = decoded.layout
        first = source.components[0]
        layout = Layout(source.width, source.height, standard_components(first.h, first.v),
                        source.restart_interval)
        quantization = {0: decoded.quantization[first.tq],
                        1: decoded.quantization[source.components[1].tq]}
        prepared = SimpleNamespace(layout=layout, planes=None, quantization=quantization,
                                   coefficients=decoded.coefficients)
        return self.encode_prepared(prepared, "optimized")


def plane_values(plane):
    return (value for row in plane for value in row)


def image_values(image):
    return (value for row in image for pixel in row for value in pixel)


def psnr_from_error(error, count):
    return "inf" if error == 0 else f"{10 * log10(65025 * count / error):.2f}"


def psnr(first, second):
    error = count = 0
    for a, b in zip(first, second):
        difference = a - b
        error += difference * difference
        count += 1
    return psnr_from_error(error, count)


def image_psnr(first, second):
    return psnr(image_values(first), image_values(second))


def quality_metrics(original, original_planes, decoded):
    values = [psnr(plane_values(first), plane_values(second))
              for first, second in zip(original_planes, decoded.expanded)]
    differences = [abs(a - b) for a, b in zip(image_values(original), image_values(decoded.image))]
    error = sum(difference * difference for difference in differences)
    values.append(psnr_from_error(error, len(differences)))
    return values, max(differences)


def bits_per_pixel(byte_count, width, height):
    numerator, denominator = 8 * byte_count, width * height
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def write_lines(path, lines):
    with open(path, "w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line + "\n")


class Experiment:
    def __init__(self, image, parameters, codec, stream):
        self.image, self.parameters, self.codec, self.stream = image, parameters, codec, stream
        self.width, self.height = len(image[0]), len(image)
        self.original_planes = color.split_planes(image)
        self.quality = parameters["qualities"][0]
        self.sampling = parameters["sampling"]
        self.mode = parameters["huffman"]
        self.restart = parameters["restart_interval"]
        self.prepared = {}
        self.encodings = {}
        self.decodings = {}

    def encoding(self, quality, sampling=None, mode=None):
        sampling = self.sampling if sampling is None else sampling
        mode = self.mode if mode is None else mode
        key = quality, sampling, mode
        if key not in self.encodings:
            if (quality, sampling) not in self.prepared:
                self.prepared[quality, sampling] = self.codec.prepare(self.image, quality, sampling, self.restart)
            self.encodings[key] = self.codec.encode_prepared(self.prepared[quality, sampling], mode)
        return self.encodings[key]

    def decoding(self, quality, sampling=None):
        sampling = self.sampling if sampling is None else sampling
        key = quality, sampling
        if key not in self.decodings:
            self.decodings[key] = self.codec.decode(self.encoding(quality, sampling).data)
        return self.decodings[key]

    def rate_distortion(self):
        lines = ["quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error"]
        for quality in self.parameters["qualities"]:
            standard = self.encoding(quality, mode="standard")
            optimized = self.encoding(quality, mode="optimized")
            selected = self.encoding(quality)
            metrics, maximum = quality_metrics(self.image, self.original_planes, self.decoding(quality))
            row = [str(quality), str(len(standard.data)), str(len(optimized.data)),
                   bits_per_pixel(len(selected.data), self.width, self.height), *metrics, str(maximum)]
            lines.append(",".join(row))
        return lines

    def block_statistics(self, encoded, decoded):
        lines = [f"blocks {len(encoded.layout.blocks)}"]
        errors = []
        for number, (block, sequence) in enumerate(zip(encoded.layout.blocks, encoded.coefficients)):
            original = encoded.planes[block.component]
            restored = decoded.planes[block.component]
            error = 0
            for y in range(8 * block.by, 8 * block.by + 8):
                for x in range(8 * block.bx, 8 * block.bx + 8):
                    difference = original[y][x] - restored[y][x]
                    error += difference * difference
            errors.append(error)
            nonzero = sum(value != 0 for value in sequence[1:])
            last = max((index for index, value in enumerate(sequence) if value != 0), default=0)
            lines.append(
                f"block {number} {COMPONENT_NAMES[block.component]} {block.bx} {block.by} "
                f"dc {sequence[0]} diff {encoded.differences[number]} nonzero {nonzero} "
                f"last {last} bits {encoded.block_bits[number]} sse {error}"
            )
        return lines, errors

    def huffman_lines(self, encoded):
        lines = []
        for key, name in zip(TABLE_KEYS, TABLE_NAMES):
            table = encoded.tables[key]
            frequencies = encoded.frequencies[key]
            bits = sum(frequencies[symbol] * table.codes[symbol][0] for symbol in table.symbols)
            lines.append(
                f"table {name} class {key[0]} id {key[1]} symbols {len(table.symbols)} "
                f"coded {sum(frequencies)} bits {bits}"
            )
            lines.append("counts " + " ".join(map(str, table.counts)))
            for symbol in table.symbols:
                length, code = table.codes[symbol]
                lines.append(
                    f"symbol {symbol:02x} length {length} code {code:0{length}b} count {frequencies[symbol]}"
                )
        return lines

    def thumbnail(self, decoded):
        layout = decoded.layout
        dc_values = {(block.component, block.bx, block.by): sequence[0]
                     for block, sequence in zip(layout.blocks, decoded.coefficients)}
        image = []
        for y in range((self.height + 7) // 8):
            row = []
            for x in range((self.width + 7) // 8):
                values = []
                for index, component in enumerate(layout.components):
                    bx, by = x * component.h // layout.hmax, y * component.v // layout.vmax
                    dc = dc_values[index, bx, by]
                    divisor = decoded.quantization[component.tq][0][0]
                    values.append(color.clamp((dc * divisor + 4) // 8 + 128))
                row.append(color.to_rgb(*values))
            image.append(row)
        return image

    def reference_report(self, encoded, decoded, errors):
        layout = encoded.layout
        counts = [component.h * component.v * layout.mcus for component in layout.components]
        lines = [
            f"image {self.width} {self.height}",
            f"sampling {self.sampling} mcu {8 * layout.hmax} {8 * layout.vmax} grid {layout.mx} {layout.my}",
            f"padded {8 * layout.hmax * layout.mx} {8 * layout.vmax * layout.my}",
            "blocks " + " ".join(map(str, counts)),
            f"restart_interval {self.restart} markers {len(layout.intervals) - 1}",
            f"huffman {self.mode}",
            f"quality {self.quality}",
        ]
        for identifier in range(2):
            lines.append(f"quant {identifier} " + " ".join(map(str, dct.zigzag(encoded.quantization[identifier]))))
        lines.append("symbols " + " ".join(str(sum(encoded.frequencies[key])) for key in TABLE_KEYS))
        eob = encoded.frequencies[1, 0][0] + encoded.frequencies[1, 1][0]
        zrl = encoded.frequencies[1, 0][0xF0] + encoded.frequencies[1, 1][0xF0]
        lines.append(f"eob {eob} zrl {zrl}")
        lines.append(f"zero_ac_blocks {sum(not any(sequence[1:]) for sequence in encoded.coefficients)}")
        nonzero = [sum(sequence[index] != 0 for sequence in encoded.coefficients) for index in range(64)]
        lines.append("nonzero " + " ".join(map(str, nonzero)))
        for component, name in enumerate(COMPONENT_NAMES):
            numbers = [index for index, block in enumerate(layout.blocks) if block.component == component]
            bits = sum(encoded.block_bits[index] for index in numbers)
            nonzero_count = sum(sum(value != 0 for value in encoded.coefficients[index]) for index in numbers)
            error = sum(errors[index] for index in numbers)
            lines.append(f"component {name} bits {bits} nonzero {nonzero_count} sse {error}")
        lines.extend([
            f"padding_bits {encoded.padding_bits}",
            f"stuffed_bytes {encoded.stuffed_bytes}",
            f"header_bytes {encoded.header_bytes}",
            f"scan_bytes {encoded.scan_bytes}",
            f"total_bytes {len(encoded.data)}",
        ])
        for index, (first, count, position, length) in enumerate(encoded.intervals):
            lines.append(f"interval {index} {first} {count} {position} {length}")
        histogram = [0] * 8
        for first, second in zip(image_values(self.image), image_values(decoded.image)):
            histogram[bisect_right((1, 2, 4, 8, 16, 32, 64), abs(first - second))] += 1
        lines.append("error_histogram " + " ".join(map(str, histogram)))
        for keep in self.parameters["truncate"]:
            plane = self.codec.reconstruct_component(
                decoded.layout, 0, decoded.coefficients, decoded.quantization, keep
            )
            cropped = [row[:self.width] for row in plane[:self.height]]
            value = psnr(plane_values(self.original_planes[0]), plane_values(cropped))
            lines.append(f"truncate {keep} {value}")
        return lines

    def sampling_comparison(self):
        lines = []
        for sampling in ("444", "422", "420"):
            encoded = self.encoding(self.quality, sampling)
            metrics, _ = quality_metrics(self.image, self.original_planes, self.decoding(self.quality, sampling))
            lines.append(f"sampling_compare {sampling} {len(encoded.data)} " + " ".join(metrics[1:]))
        return lines

    def generations(self, reference, reference_decoded):
        lines = []
        previous = self.image
        for generation in range(1, self.parameters["generations"] + 1):
            if generation == 1:
                encoded, decoded = reference, reference_decoded
            else:
                encoded = self.codec.encode(previous, self.quality, self.sampling, self.mode, self.restart)
                decoded = self.codec.decode(encoded.data)
            changed = sum(first != second for row_a, row_b in zip(previous, decoded.image)
                          for first, second in zip(row_a, row_b))
            lines.append(
                f"generation {generation} {len(encoded.data)} {image_psnr(self.image, decoded.image)} {changed}"
            )
            previous = decoded.image
        return lines

    def quality_search(self):
        target = self.parameters["target_bytes"]
        lower, upper = 1, 100
        lines = []
        while lower < upper:
            middle = (lower + upper + 1) // 2
            size = len(self.encoding(middle).data)
            lines.append(f"rate_control_step {middle} {size}")
            if size <= target:
                lower = middle
            else:
                upper = middle - 1
        size = len(self.encoding(lower).data)
        fits = "yes" if size <= target else "no"
        value = image_psnr(self.image, self.decoding(lower).image)
        lines.append(f"rate_control {lower} {size} {fits} {value}")
        return lines

    def stream_report(self, decoded, repaired, repaired_decoded):
        lines = [f"stream_segment {position} {name} {length}" for position, name, length in decoded.segments]
        layout = decoded.layout
        lines.append(f"stream_image {layout.width} {layout.height}")
        for component in layout.components:
            lines.append(
                f"stream_component {component.identifier} {component.h} {component.v} "
                f"{component.tq} {component.td} {component.ta}"
            )
        for identifier in sorted(decoded.quantization):
            values = " ".join(map(str, dct.zigzag(decoded.quantization[identifier])))
            lines.append(f"stream_quant {identifier} {values}")
        for table_class, identifier in sorted(decoded.tables):
            table = decoded.tables[table_class, identifier]
            longest = max(length for length, count in enumerate(table.counts, 1) if count > 0)
            lines.append(f"stream_huffman {table_class} {identifier} symbols {len(table.symbols)} longest {longest}")
        counts = {state: sum(result["state"] == state for result in decoded.states)
                  for state in ("ok", "damaged", "lost")}
        lines.append(
            f"stream_restart {layout.restart_interval} intervals {len(layout.intervals)} "
            f"ok {counts['ok']} damaged {counts['damaged']} lost {counts['lost']}"
        )
        for index, ((first, count), result) in enumerate(zip(layout.intervals, decoded.states)):
            state = result["state"]
            if state == "damaged":
                state += (f" {result['kind']} mcu {result['mcu']} offset {result['offset']} "
                          f"resync {result['resync']}")
            lines.append(f"stream_interval {index} {first} {count} {state}")
        lines.append(f"stream_scan_bytes {decoded.scan_bytes}")
        identical = "yes" if decoded.image == repaired_decoded.image else "no"
        lines.append(
            f"repair {len(repaired.data)} {repaired.header_bytes} {repaired.scan_bytes} identical {identical}"
        )
        return lines

    def run(self):
        rate_lines = self.rate_distortion()
        reference = self.encoding(self.quality)
        reference_decoded = self.decoding(self.quality)
        block_lines, block_errors = self.block_statistics(reference, reference_decoded)
        report = self.reference_report(reference, reference_decoded, block_errors)
        report.extend(self.sampling_comparison())
        report.extend(self.generations(reference, reference_decoded))
        report.extend(self.quality_search())
        stream_decoded = self.codec.decode(self.stream)
        repaired = self.codec.repair(stream_decoded)
        repaired_decoded = self.codec.decode(repaired.data)
        report.extend(self.stream_report(stream_decoded, repaired, repaired_decoded))
        Path("output").mkdir(exist_ok=True)
        write_lines("output/rate_distortion.csv", rate_lines)
        write_ppm("output/decoded.ppm", reference_decoded.image)
        write_hex("output/bitstream.hex", reference.data)
        write_ppm("output/thumbnail.ppm", self.thumbnail(reference_decoded))
        write_lines("output/huffman_tables.txt", self.huffman_lines(reference))
        write_lines("output/blocks.txt", block_lines)
        write_ppm("output/stream_decoded.ppm", stream_decoded.image)
        write_hex("output/repaired.hex", repaired.data)
        write_lines("output/report.txt", report)


def main():
    image = read_ppm("input/image.ppm")
    parameters = read_params("input/params.txt")
    codec = Codec(*read_tables("input/tables.txt"))
    stream = read_hex("input/stream.hex")
    Experiment(image, parameters, codec, stream).run()


if __name__ == "__main__":
    main()
