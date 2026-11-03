"""Encode, inspect, damage, and decode QR Model 2 symbols using input tables."""

from collections import Counter
from pathlib import Path

import bitstream
import masking
import matrix
import reed_solomon
import render


LEVELS = ("L", "M", "Q", "H")
MODES = ("NUMERIC", "ALPHANUMERIC", "BYTE")
INDICATORS = {"NUMERIC": 1, "ALPHANUMERIC": 2, "BYTE": 4}
ERROR_KINDS = ("level", "mode", "version", "mask", "text", "charset", "capacity")


def count_width(mode, version):
    widths = (12, 11, 16) if version == 10 else (10, 9, 8)
    return widths[MODES.index(mode)]


def data_width(mode, count):
    if mode == "NUMERIC":
        return 10 * (count // 3) + (0, 4, 7)[count % 3]
    if mode == "ALPHANUMERIC":
        return 11 * (count // 2) + 6 * (count % 2)
    return 8 * count


def encodable(mode, character):
    if mode == "NUMERIC":
        return "0" <= character <= "9"
    if mode == "ALPHANUMERIC":
        return character in bitstream.ALPHANUMERIC_VALUES
    return 32 <= ord(character) <= 126


def segment_width(mode, text, version):
    return 4 + count_width(mode, version) + data_width(mode, len(text))


def groups(mode, text):
    step = {"NUMERIC": 3, "ALPHANUMERIC": 2, "BYTE": 1}[mode]
    for start in range(0, len(text), step):
        characters = text[start:start + step]
        if mode == "NUMERIC":
            value = int(characters)
            width = (0, 4, 7, 10)[len(characters)]
        elif mode == "ALPHANUMERIC":
            value = bitstream.ALPHANUMERIC_VALUES[characters[0]]
            width = 6
            if len(characters) == 2:
                value = 45 * value + bitstream.ALPHANUMERIC_VALUES[characters[1]]
                width = 11
        else:
            value, width = ord(characters), 8
        yield value, width, characters


def mixed_segments(text, version):
    invalid = {mode: [0] for mode in MODES}
    for character in text:
        for mode in MODES:
            invalid[mode].append(invalid[mode][-1] + int(not encodable(mode, character)))
    costs = [0] * (len(text) + 1)
    choices = [None] * (len(text) + 1)
    for end in range(1, len(text) + 1):
        best = None
        for start in range(end):
            for mode in MODES:
                if invalid[mode][end] != invalid[mode][start]:
                    continue
                cost = costs[start] + 4 + count_width(mode, version)
                cost += data_width(mode, end - start)
                if best is None or cost < best:
                    best = cost
                    choices[end] = start, mode
        costs[end] = best
    segments = []
    end = len(text)
    while end:
        start, mode = choices[end]
        segments.append((mode, text[start:end]))
        end = start
    segments.reverse()
    return segments, costs[-1]


def assemble_bits(segments, version):
    writer = bitstream.BitWriter()
    lines = []
    for mode, text in segments:
        indicator = INDICATORS[mode]
        width = count_width(mode, version)
        writer.write(indicator, 4)
        writer.write(len(text), width)
        lines.append(f"segment {mode} indicator {indicator:04b} count {len(text)} "
                     f"{len(text):0{width}b}")
        for value, group_width, characters in groups(mode, text):
            writer.write(value, group_width)
            lines.append(f'group {value} {value:0{group_width}b} "{characters}"')
    return writer.value(), lines


def pad_bits(bits, capacity):
    terminator = min(4, capacity - len(bits))
    padded = bits + "0" * terminator
    zero_fill = (-len(padded)) % 8
    padded += "0" * zero_fill
    pad_count = (capacity - len(padded)) // 8
    padded += "".join("11101100" if index % 2 == 0 else "00010001"
                      for index in range(pad_count))
    return padded, (terminator, zero_fill, pad_count)


class BlockLayout:
    def __init__(self, degree, first_count, first_size, second_count, second_size):
        self.degree = degree
        self.lengths = [first_size] * first_count + [second_size] * second_count
        self.count = len(self.lengths)
        self.data = sum(self.lengths)
        self.capacity = 8 * self.data
        self.total = self.data + self.degree * self.count
        self.placement = []
        for position in range(max(self.lengths)):
            for block, length in enumerate(self.lengths):
                if position < length:
                    self.placement.append((block, position))
        for offset in range(self.degree):
            for block, length in enumerate(self.lengths):
                self.placement.append((block, length + offset))

    def encode(self, data):
        blocks = []
        start = 0
        for length in self.lengths:
            words = data[start:start + length]
            blocks.append(words + reed_solomon.parity(words, self.degree))
            start += length
        interleaved = [blocks[block][position] for block, position in self.placement]
        return blocks, interleaved

    def deinterleave(self, codewords):
        blocks = [[0] * (length + self.degree) for length in self.lengths]
        for value, (block, position) in zip(codewords, self.placement):
            blocks[block][position] = value
        return blocks


class Geometry:
    def __init__(self, version, alignments):
        self.size = 17 + 4 * version
        self.symbol, self.areas = matrix.function_matrix(version, alignments)
        self.order = matrix.reading_order(self.areas)
        self.indices = {position: index for index, position in enumerate(self.order)}
        self.data_modules = len(self.order)
        self.function_modules = self.size * self.size - self.data_modules


class Request:
    def __init__(self, fields, text):
        self.identifier, self.level_token, self.mode_token = fields[:3]
        self.version_token, self.mask_token = fields[3:]
        self.text = text
        self.splits = {}

    def split(self, version):
        category = 10 if version == 10 else 1
        if category not in self.splits:
            if self.mode == "MIXED":
                result = mixed_segments(self.text, version)
            else:
                result = [(self.mode, self.text)], segment_width(self.mode, self.text, version)
            self.splits[category] = result
        return self.splits[category]

    def prepare(self, codec):
        if self.level_token not in LEVELS + tuple(level + "+" for level in LEVELS):
            return f"level {self.level_token}"
        if self.mode_token not in MODES + ("AUTO", "MIXED"):
            return f"mode {self.mode_token}"
        if self.version_token not in ("AUTO",) + tuple(str(value) for value in range(1, 11)):
            return f"version {self.version_token}"
        if self.mask_token not in ("AUTO",) + tuple(str(value) for value in range(8)):
            return f"mask {self.mask_token}"
        if not self.text:
            return "text"
        if self.mode_token in ("NUMERIC", "ALPHANUMERIC"):
            for position, character in enumerate(self.text):
                if not encodable(self.mode_token, character):
                    return f"charset position {position}"
        self.mode = self.mode_token
        if self.mode == "AUTO":
            self.mode = next(mode for mode in MODES
                             if all(encodable(mode, character) for character in self.text))
        base_level = self.level_token[0]
        candidates = range(1, 11) if self.version_token == "AUTO" else (int(self.version_token),)
        self.version = None
        for version in candidates:
            bits = self.split(version)[1]
            capacity = codec.tables[version, base_level].capacity
            if bits <= capacity:
                self.version = version
                break
        if self.version is None:
            return f"capacity bits {bits} capacity {capacity}"
        self.segments, self.bit_count = self.split(self.version)
        self.level = base_level
        if self.level_token.endswith("+"):
            for level in LEVELS[LEVELS.index(base_level):]:
                if self.bit_count <= codec.tables[self.version, level].capacity:
                    self.level = level
        self.boosted = self.level != base_level
        return None


def read_inputs():
    requests = []
    for line in Path("input/requests.txt").read_text(encoding="ascii").splitlines():
        header, text = line.split(":", 1)
        requests.append(Request(header.split(" "), text))
    params = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, value = line.split(" ")
        params[name] = int(value)
    tables, alignments = {}, {}
    for line in Path("input/tables.txt").read_text(encoding="ascii").splitlines():
        fields = line.split(" ")
        version = int(fields[1])
        if fields[0] == "block":
            tables[version, fields[2]] = BlockLayout(*map(int, fields[3:]))
        else:
            alignments[version] = list(map(int, fields[2:]))
    damage = {}
    for line in Path("input/damage.txt").read_text(encoding="ascii").splitlines():
        identifier, operation, *arguments = line.split(" ")
        if operation == "flip":
            entry = (operation, *map(int, arguments))
        elif operation == "fill":
            entry = (operation, *map(int, arguments[:4]), int(arguments[4] == "dark"))
        else:
            entry = (operation,)
        damage.setdefault(identifier, []).append(entry)
    lines = Path("input/scans.txt").read_text(encoding="ascii").splitlines()
    scans = []
    index = 0
    while index < len(lines):
        name = lines[index].split(" ")[1]
        size = len(lines[index + 1])
        symbol = [[int(character == "#") for character in line]
                  for line in lines[index + 1:index + 1 + size]]
        scans.append((name, symbol))
        index += size + 1
    return requests, params, tables, alignments, damage, scans


class Encoding:
    def __init__(self, request, codec):
        self.request = request
        self.layout = codec.geometry(request.version)
        self.block_layout = codec.tables[request.version, request.level]
        self.raw_bits, self.trace = assemble_bits(request.segments, request.version)
        self.padded_bits, self.padding = pad_bits(self.raw_bits, self.block_layout.capacity)
        data = bitstream.to_codewords(self.padded_bits)
        self.blocks, self.codewords = self.block_layout.encode(data)
        unmasked = [row[:] for row in self.layout.symbol]
        for bit, (x, y) in zip(bitstream.from_codewords(self.codewords), self.layout.order):
            unmasked[y][x] = int(bit)
        candidates = []
        self.penalties = []
        for mask in range(8):
            symbol = masking.apply(unmasked, self.layout.order, mask)
            information = matrix.format_information(request.level, mask)
            for positions in matrix.format_positions(self.layout.size):
                matrix.write_value(symbol, positions, information)
            candidates.append(symbol)
            self.penalties.append(masking.penalties(symbol))
        if request.mask_token == "AUTO":
            self.mask = min(range(8), key=lambda mask: sum(self.penalties[mask]))
        else:
            self.mask = int(request.mask_token)
        self.symbol = candidates[self.mask]
        self.dark = sum(sum(row) for row in self.symbol)


def codes_lines(encoding, codec):
    request = encoding.request
    layout, blocks = encoding.layout, encoding.block_layout
    version, level = request.version, request.level
    lines = [f"symbol version {version} level {level} mask {encoding.mask} size {layout.size}"]
    segments = " ".join(f"{mode}:{len(text)}" for mode, text in request.segments)
    lines.append(f"segments {len(request.segments)} {segments}")
    alternatives = []
    for mode in MODES:
        possible = all(encodable(mode, character) for character in request.text)
        value = str(segment_width(mode, request.text, version)) if possible else "-"
        alternatives.append(f"{mode} {value}")
    mixed_bits = request.bit_count if request.mode == "MIXED" else mixed_segments(request.text, version)[1]
    alternatives.append(f"MIXED {mixed_bits}")
    lines.append(f"bits data {request.bit_count} capacity {blocks.capacity} alternatives "
                 + " ".join(alternatives))
    fits = []
    for candidate_level in LEVELS:
        fitting = next((candidate for candidate in range(1, 11)
                        if request.split(candidate)[1] <= codec.tables[candidate, candidate_level].capacity), "-")
        fits.append(f"{candidate_level} {fitting}")
    lines.append("fits " + " ".join(fits))
    remainder = layout.data_modules - 8 * blocks.total
    lines.append(f"modules function {layout.function_modules} data {layout.data_modules} "
                 f"remainder {remainder} dark {encoding.dark}")
    information = matrix.format_information(level, encoding.mask)
    version_text = f"{matrix.version_information(version):018b}" if version >= 7 else "none"
    lines.append(f"format {information:015b} version {version_text}")
    for mask, (n1, n2, n3, n4) in enumerate(encoding.penalties):
        lines.append(f"penalty {mask} n1 {n1} n2 {n2} n3 {n3} n4 {n4} total {n1 + n2 + n3 + n4}")
    lines.extend(render.symbol_lines(encoding.symbol))
    return lines


def codeword_lines(encoding):
    request, layout = encoding.request, encoding.block_layout
    lines = [f"request {request.identifier} version {request.version} level {request.level} "
             f"blocks {layout.count} data {layout.data} ec_per_block {layout.degree} total {layout.total}"]
    for block, (words, length) in enumerate(zip(encoding.blocks, layout.lengths)):
        lines.append(f"block {block} data {bitstream.hexadecimal(words[:length])}")
        lines.append(f"block {block} ec {bitstream.hexadecimal(words[length:])}")
    lines.append("interleaved " + bitstream.hexadecimal(encoding.codewords))
    return lines


def bitstream_lines(encoding):
    request = encoding.request
    lines = [f"request {request.identifier} version {request.version} bits {request.bit_count} "
             f"capacity {encoding.block_layout.capacity}"]
    lines.extend(encoding.trace)
    terminator, zero_fill, pad_count = encoding.padding
    lines.append(f"terminator {terminator} zero_fill {zero_fill} pad_bytes {pad_count}")
    return lines


def read_image(path):
    lines = path.read_text(encoding="ascii").splitlines()
    width, height = map(int, lines[1].split(" "))
    pixels = [[int(value) for value in line] for line in lines[2:2 + height]]
    dark = [(x, y) for y, row in enumerate(pixels) for x, value in enumerate(row) if value]
    left = min(x for x, y in dark)
    right = max(x for x, y in dark)
    top = min(y for x, y in dark)
    run = 0
    while left + run < width and pixels[top][left + run] == 1:
        run += 1
    unit = run // 7
    size = (right - left + 1) // unit
    symbol = [[pixels[top + unit * y][left + unit * x] for x in range(size)]
              for y in range(size)]
    well_formed = True
    for y in range(height):
        for x in range(width):
            expected = 0
            if left <= x < left + unit * size and top <= y < top + unit * size:
                expected = symbol[(y - top) // unit][(x - left) // unit]
            if pixels[y][x] != expected:
                well_formed = False
    status = "ok" if well_formed else "bad"
    line = f"image {width} {height} quiet {left // unit} scale {unit} size {size} {status}"
    return symbol, line


def rotate(symbol):
    size = len(symbol)
    return [[symbol[size - 1 - x][y] for x in range(size)] for y in range(size)]


def transpose(symbol):
    return [list(column) for column in zip(*symbol)]


def finder_rotation(symbol):
    size = len(symbol)
    corners = ((size - 7, size - 7), (size - 7, 0), (0, 0), (0, size - 7))
    scores = []
    for left, top in corners:
        score = 0
        for y in range(7):
            for x in range(7):
                expected = int(max(abs(x - 3), abs(y - 3)) != 2)
                score += int(symbol[top + y][left + x] == expected)
        scores.append(score)
    return min(range(4), key=lambda index: scores[index])


class Attempt:
    def __init__(self):
        self.lines = []
        self.text = None
        self.blocks = []


def read_segment(reader, mode, count):
    characters = []
    while count:
        if mode == "NUMERIC":
            group_size = min(3, count)
            value = reader.read((0, 4, 7, 10)[group_size])
            if value >= 10 ** group_size:
                return None
            characters.append(f"{value:0{group_size}d}")
        elif mode == "ALPHANUMERIC":
            group_size = min(2, count)
            value = reader.read(11 if group_size == 2 else 6)
            if value >= (2025 if group_size == 2 else 45):
                return None
            if group_size == 2:
                characters.append(bitstream.ALPHANUMERIC[value // 45])
            characters.append(bitstream.ALPHANUMERIC[value % 45])
        else:
            group_size = 1
            value = reader.read(8)
            if not 32 <= value <= 126:
                return None
            characters.append(chr(value))
        count -= group_size
    return "".join(characters)


def parse_data(attempt, bits, version):
    reader = bitstream.BitReader(bits)
    text = []
    end = 0
    modes = {value: mode for mode, value in INDICATORS.items()}
    while reader.remaining() >= 4:
        indicator = reader.read(4)
        if indicator == 0:
            break
        if indicator not in modes:
            attempt.lines.append(f"parse failed indicator {indicator:04b}")
            return
        mode = modes[indicator]
        width = count_width(mode, version)
        if reader.remaining() < width:
            attempt.lines.append(f"parse failed length {mode}")
            return
        count = reader.read(width)
        if reader.remaining() < data_width(mode, count):
            attempt.lines.append(f"parse failed length {mode}")
            return
        segment = read_segment(reader, mode, count)
        if segment is None:
            attempt.lines.append(f"parse failed value {mode}")
            return
        text.append(segment)
        attempt.lines.append(f"segment {mode} {count}")
        end = reader.position
    expected, _ = pad_bits(bits[:end], len(bits))
    attempt.lines.append("padding " + ("ok" if expected == bits else "bad"))
    attempt.text = "".join(text)
    attempt.lines.append(f'text "{attempt.text}"')


class Codec:
    def __init__(self, tables, alignments):
        self.tables = tables
        self.alignments = alignments
        self.geometries = {}
        self.formats = [(matrix.format_information(level, mask), level, mask)
                        for level in LEVELS for mask in range(8)]
        self.versions = [(matrix.version_information(version), version) for version in range(7, 41)]

    def geometry(self, version):
        if version not in self.geometries:
            self.geometries[version] = Geometry(version, self.alignments[version])
        return self.geometries[version]

    def attempt(self, symbol):
        attempt = Attempt()
        size = len(symbol)
        version = (size - 17) // 4
        first, second = (matrix.read_value(symbol, positions)
                         for positions in matrix.format_positions(size))
        nearest_first = min(self.formats, key=lambda item: (first ^ item[0]).bit_count())
        nearest_second = min(self.formats, key=lambda item: (second ^ item[0]).bit_count())
        distance_first = (first ^ nearest_first[0]).bit_count()
        distance_second = (second ^ nearest_second[0]).bit_count()
        prefix = f"format {first:015b} {second:015b} distance {distance_first} {distance_second}"
        chosen = nearest_second if distance_second < distance_first else nearest_first
        if min(distance_first, distance_second) > 3:
            attempt.lines.append(prefix + " unreadable")
            return attempt
        _, level, mask = chosen
        attempt.lines.append(prefix + f" level {level} mask {mask}")
        if version >= 7:
            first, second = (matrix.read_value(symbol, positions)
                             for positions in matrix.version_positions(size))
            nearest_first = min(self.versions, key=lambda item: (first ^ item[0]).bit_count())
            nearest_second = min(self.versions, key=lambda item: (second ^ item[0]).bit_count())
            distance_first = (first ^ nearest_first[0]).bit_count()
            distance_second = (second ^ nearest_second[0]).bit_count()
            prefix = f"version {first:018b} {second:018b} distance {distance_first} {distance_second}"
            chosen = nearest_second if distance_second < distance_first else nearest_first
            if min(distance_first, distance_second) > 3:
                attempt.lines.append(prefix + " unreadable")
                return attempt
            attempt.lines.append(prefix + f" decoded {chosen[1]}")
            if chosen[1] != version:
                return attempt
        geometry = self.geometry(version)
        layout = self.tables[version, level]
        unmasked = masking.apply(symbol, geometry.order, mask)
        bits = "".join(str(unmasked[y][x]) for x, y in geometry.order[:8 * layout.total])
        blocks = layout.deinterleave(bitstream.to_codewords(bits))
        corrected_blocks = []
        failed = False
        for block, received in enumerate(blocks):
            syndromes, corrected, positions = reed_solomon.correct(received, layout.degree)
            prefix = f"block {block} syndromes {bitstream.hexadecimal(syndromes)}"
            if corrected is None:
                status = "failed"
                attempt.lines.append(prefix + " failed")
                failed = True
            elif positions:
                status = "corrected"
                attempt.lines.append(prefix + " corrected " + " ".join(map(str, positions)))
            else:
                status = "ok"
                attempt.lines.append(prefix + " ok")
            attempt.blocks.append((status, len(positions)))
            corrected_blocks.append(corrected)
        if failed:
            return attempt
        data = []
        for words, length in zip(corrected_blocks, layout.lengths):
            data.extend(words[:length])
        parse_data(attempt, bitstream.from_codewords(data), version)
        return attempt

    def decode(self, symbol):
        rotations = finder_rotation(symbol)
        oriented = symbol
        for _ in range(rotations):
            oriented = rotate(oriented)
        adopted = self.attempt(oriented)
        mirrored = False
        if adopted.text is None:
            second = self.attempt(transpose(oriented))
            if second.text is not None:
                adopted = second
                mirrored = True
        label = "yes" if mirrored else "no"
        adopted.lines.insert(0, f"orientation rotations {rotations} mirrored {label}")
        return adopted


def damaged_symbol(encoding, operations):
    symbol = [row[:] for row in encoding.symbol]
    for operation in operations:
        if operation[0] == "flip":
            _, x, y = operation
            symbol[y][x] ^= 1
        elif operation[0] == "fill":
            _, left, top, width, height, color = operation
            for y in range(top, top + height):
                for x in range(left, left + width):
                    symbol[y][x] = color
    counts = Counter()
    damaged_words = [set() for _ in range(encoding.block_layout.count)]
    for y, row in enumerate(symbol):
        for x, value in enumerate(row):
            if value == encoding.symbol[y][x]:
                continue
            area = encoding.layout.areas[y][x]
            if area == matrix.FUNCTION:
                counts["function"] += 1
            elif area == matrix.FORMAT:
                counts["format"] += 1
            elif area == matrix.VERSION:
                counts["version"] += 1
            else:
                index = encoding.layout.indices[x, y]
                if index < 8 * encoding.block_layout.total:
                    counts["data"] += 1
                    block, position = encoding.block_layout.placement[index // 8]
                    damaged_words[block].add(position)
                else:
                    counts["remainder"] += 1
    for operation in operations:
        if operation[0] == "rotate":
            symbol = rotate(symbol)
        elif operation[0] == "mirror":
            symbol = transpose(symbol)
    details = " ".join(f"{area} {counts[area]}" for area in ("function", "format", "version", "data", "remainder"))
    lines = [f"check damaged operations {len(operations)}", f"damage changed {sum(counts.values())} {details}"]
    errors = " ".join(str(len(words)) for words in damaged_words)
    lines.append(f"errors {errors} limit {encoding.block_layout.degree // 2}")
    return symbol, lines


def tolerance(encoding, codec, color):
    size = encoding.layout.size
    for side in range(1, size + 1):
        symbol = [row[:] for row in encoding.symbol]
        start = (size - side) // 2
        for y in range(start, start + side):
            for x in range(start, start + side):
                symbol[y][x] = color
        result = codec.decode(symbol)
        if result.text != encoding.request.text:
            return side - 1
    return size


class Summary:
    def __init__(self):
        self.totals = Counter()
        self.errors = Counter()
        self.modes = Counter()
        self.levels = Counter()
        self.versions = Counter()
        self.masks = Counter()
        self.checks = Counter()
        self.blocks = Counter()
        self.scans = Counter()

    def record_error(self, error):
        self.errors[error.split(" ")[0]] += 1

    def record_encoding(self, encoding):
        request = encoding.request
        self.totals["encoded"] += 1
        self.modes[request.mode] += 1
        self.levels[request.level] += 1
        self.totals["boosted"] += int(request.boosted)
        self.versions[request.version] += 1
        self.masks[encoding.mask] += 1
        self.totals["segments"] += len(request.segments)
        self.totals["data"] += encoding.block_layout.data
        self.totals["ec"] += encoding.block_layout.degree * encoding.block_layout.count
        self.totals["modules"] += encoding.layout.size * encoding.layout.size
        self.totals["dark"] += encoding.dark

    def record_check(self, attempt, text):
        if attempt.text is None:
            result = "failed"
        else:
            result = "ok" if attempt.text == text else "mismatch"
        self.checks[result] += 1
        for status, positions in attempt.blocks:
            self.blocks[status] += 1
            self.totals["corrected_positions"] += positions
        return result

    def lines(self, request_count):
        lines = [f"requests {request_count} encoded {self.totals['encoded']} errors {sum(self.errors.values())}"]
        lines.append("error_kinds " + " ".join(f"{kind} {self.errors[kind]}" for kind in ERROR_KINDS))
        lines.append("modes " + " ".join(f"{mode} {self.modes[mode]}" for mode in MODES + ("MIXED",)))
        lines.append("levels " + " ".join(f"{level} {self.levels[level]}" for level in LEVELS)
                     + f" boosted {self.totals['boosted']}")
        lines.append("versions " + " ".join(str(self.versions[version]) for version in range(1, 11)))
        lines.append("masks " + " ".join(str(self.masks[mask]) for mask in range(8)))
        lines.append(f"segments {self.totals['segments']} data_codewords {self.totals['data']} "
                     f"ec_codewords {self.totals['ec']}")
        lines.append(f"modules {self.totals['modules']} dark {self.totals['dark']}")
        lines.append(f"checks {sum(self.checks.values())} "
                     + " ".join(f"{status} {self.checks[status]}" for status in ("ok", "mismatch", "failed")))
        lines.append("blocks " + " ".join(f"{status} {self.blocks[status]}" for status in ("ok", "corrected", "failed"))
                     + f" codewords {self.totals['corrected_positions']}")
        lines.append(f"scans {sum(self.scans.values())} decoded {self.scans['decoded']} failed {self.scans['failed']}")
        return lines


def check_lines(encoding, codec, params, operations, summary, output):
    request = encoding.request
    path = output / f"qr_{request.identifier}.pbm"
    path.write_text(render.pbm_text(encoding.symbol, params["quiet_zone"], params["scale"]),
                    encoding="ascii", newline="\n")
    symbol, image_line = read_image(path)
    lines = [f"request {request.identifier}", image_line, "check clean"]
    attempt = codec.decode(symbol)
    lines.extend(attempt.lines)
    lines.append("result " + summary.record_check(attempt, request.text))
    if operations:
        symbol, damage_lines = damaged_symbol(encoding, operations)
        lines.extend(damage_lines)
        attempt = codec.decode(symbol)
        lines.extend(attempt.lines)
        lines.append("result " + summary.record_check(attempt, request.text))
    light = tolerance(encoding, codec, 0)
    dark = tolerance(encoding, codec, 1)
    lines.append(f"tolerance light {light} dark {dark}")
    return lines


def capacity_lines(codec):
    lines = []
    for version in range(1, 11):
        geometry = codec.geometry(version)
        total = codec.tables[version, "L"].total
        alignment = " ".join(map(str, codec.alignments[version])) or "none"
        lines.append(f"version {version} size {geometry.size} data_modules {geometry.data_modules} "
                     f"codewords {total} remainder {geometry.data_modules - 8 * total} alignment {alignment}")
        for level in LEVELS:
            layout = codec.tables[version, level]
            maxima = []
            for mode in MODES:
                count = 0
                while 4 + count_width(mode, version) + data_width(mode, count + 1) <= layout.capacity:
                    count += 1
                maxima.append(count)
            lines.append(f"level {level} blocks {layout.count} data {layout.data} ec_per_block {layout.degree} "
                         f"numeric {maxima[0]} alphanumeric {maxima[1]} byte {maxima[2]}")
    return lines


def main():
    requests, params, tables, alignments, damage, scans = read_inputs()
    codec = Codec(tables, alignments)
    summary = Summary()
    output = Path("output")
    output.mkdir(exist_ok=True)
    reports = {name: [] for name in ("codes", "codewords", "bitstream", "selfcheck", "scans")}
    for request in requests:
        reports["codes"].append(f"request {request.identifier}")
        error = request.prepare(codec)
        if error is not None:
            reports["codes"].append("error " + error)
            summary.record_error(error)
            continue
        encoding = Encoding(request, codec)
        reports["codes"].extend(codes_lines(encoding, codec))
        reports["codewords"].extend(codeword_lines(encoding))
        reports["bitstream"].extend(bitstream_lines(encoding))
        summary.record_encoding(encoding)
        reports["selfcheck"].extend(check_lines(encoding, codec, params,
                                               damage.get(request.identifier, []), summary, output))
    for name, symbol in scans:
        reports["scans"].append(f"scan {name} size {len(symbol)}")
        attempt = codec.decode(symbol)
        reports["scans"].extend(attempt.lines)
        result = "decoded" if attempt.text is not None else "failed"
        reports["scans"].append("result " + result)
        summary.scans[result] += 1
    reports["capacity"] = capacity_lines(codec)
    reports["summary"] = summary.lines(len(requests))
    for name, lines in reports.items():
        (output / f"{name}.txt").write_text("".join(line + "\n" for line in lines),
                                          encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
