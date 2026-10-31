"""Create, inspect, repair and salvage TXAR archives of ASCII text files."""

from array import array
from dataclasses import dataclass, field
from pathlib import Path

import arith_coder
import huffman
import lz77
import lzw
from bitio import BitReader, BitWriter, DecodeError


METHODS = ("STORE", "LZW", "LZ77", "LZH", "ARITH")
STATUSES = ("ok", "repaired", "checksum", "error", "unsupported",
            "truncated", "bad_header")
NAME_BYTES = frozenset(b"abcdefghijklmnopqrstuvwxyz0123456789._-")
MODULUS = 65521


@dataclass(frozen=True)
class Parameters:
    offset_bits: int
    length_bits: int
    max_code_length: int


@dataclass
class LzStatistics:
    tokens: int
    literals: int
    matches: int
    matched: int
    longest: int
    farthest: int


@dataclass
class LzhStatistics:
    mode: str
    fixed_bits: int
    table_bits: int
    code_bits: int
    halvings: int
    litlen_used: int
    litlen_max: int
    offset_used: int
    offset_max: int
    slots: list[int]


@dataclass
class Encoding:
    name: str
    data: bytes
    payloads: list[bytes]
    best: int
    lzw_stats: lzw.Statistics
    lz77_stats: LzStatistics
    lzh_stats: LzhStatistics
    arith_stats: arith_coder.Statistics

    @property
    def payload(self):
        return self.payloads[self.best]


@dataclass
class Entry:
    number: int
    offset: int
    status: str = ""
    valid_header: bool = False
    name: str = ""
    method: int = 0
    original: int = 0
    compressed: int = 0
    checksum: int = 0
    start: int = 0
    end: int = 0
    data: bytes | None = None
    error: DecodeError | None = None
    repair: tuple[int, int, int] | None = None
    computed: int = 0


@dataclass
class ParsedArchive:
    size: int
    offset_bits: int = 0
    length_bits: int = 0
    declared: int = 0
    entries: list[Entry] = field(default_factory=list)
    error: str | None = None
    stopped: bool = False
    trailing: int = 0

    @property
    def intact(self):
        return [entry for entry in self.entries
                if entry.status in ("ok", "repaired")]


def read_inputs(directory):
    lines = (directory / "manifest.txt").read_bytes().decode("ascii").splitlines()
    values = [int(line.split(" ")[1]) for line in lines[:3]]
    parameters = Parameters(*values)
    files = []
    for line in lines[3:]:
        name = line.split(" ")[1]
        files.append((name, (directory / "files" / name).read_bytes()))
    hexadecimal = b"".join((directory / "archive.hex").read_bytes().splitlines())
    archive = bytes.fromhex(hexadecimal.decode("ascii"))
    return parameters, files, archive


def ratio(compressed, original):
    return str(1000 * compressed // original) if original else "-"


def method_name(number):
    return METHODS[number] if number < len(METHODS) else f"#{number}"


def adler32(data):
    first = 1
    second = 0
    for value in data:
        first = (first + value) % MODULUS
        second = (second + first) % MODULUS
    return second * 65536 + first


def repair_one_byte(data, stored, computed):
    delta_a = ((stored % 65536) - (computed % 65536)) % MODULUS
    delta_b = ((stored // 65536) - (computed // 65536)) % MODULUS
    if 1 <= delta_a <= 255:
        delta = delta_a
    elif MODULUS - 255 <= delta_a < MODULUS:
        delta = delta_a - MODULUS
    else:
        return None
    inverse = pow(delta % MODULUS, MODULUS - 2, MODULUS)
    distance_from_end = delta_b * inverse % MODULUS
    if not 1 <= distance_from_end <= len(data):
        return None
    position = len(data) - distance_from_end
    before = data[position]
    after = before + delta
    if not 0 <= after <= 255:
        return None
    repaired = bytearray(data)
    repaired[position] = after
    repaired = bytes(repaired)
    if adler32(repaired) != stored:
        return None
    return repaired, (position, before, after)


def decode_store(payload, original_size):
    if len(payload) < original_size:
        raise DecodeError("end_of_data", len(payload))
    return payload[:original_size]


def encode_lz77(tokens, offset_bits, length_bits):
    writer = BitWriter()
    for token in tokens:
        if isinstance(token, int):
            writer.write(0, 1)
            writer.write(token, 8)
        else:
            distance, length = token
            writer.write(1, 1)
            writer.write(distance - 1, offset_bits)
            writer.write(length - 3, length_bits)
    return writer.finish()


def decode_lz77(payload, original_size, offset_bits, length_bits):
    reader = BitReader(payload)
    output = bytearray()
    while len(output) < original_size:
        flag = reader.read(1, len(output))
        if flag == 0:
            output.append(reader.read(8, len(output)))
        else:
            distance = reader.read(offset_bits, len(output)) + 1
            length = reader.read(length_bits, len(output)) + 3
            lz77.copy_match(output, distance, length, original_size)
    return bytes(output)


def fixed_lengths(symbol_count):
    width = (symbol_count - 1).bit_length()
    shorter = (1 << width) - symbol_count
    return [width - 1 if symbol < shorter else width
            for symbol in range(symbol_count)]


def write_code_table(writer, lengths):
    symbol = 0
    while symbol < len(lengths):
        length = lengths[symbol]
        if length:
            writer.write(length, 4)
            symbol += 1
        else:
            run = 1
            while (run < 256 and symbol + run < len(lengths)
                   and lengths[symbol + run] == 0):
                run += 1
            writer.write(0, 4)
            writer.write(run - 1, 8)
            symbol += run


def check_code_table(lengths, output_position):
    positive = [length for length in lengths if length]
    if len(positive) == 1:
        valid = positive[0] == 1
    elif len(positive) >= 2:
        valid = sum(1 << (15 - length) for length in positive) == 1 << 15
    else:
        valid = True
    if not valid:
        raise DecodeError("bad_table", output_position)


def read_code_table(reader, symbol_count, output_position):
    lengths = []
    while len(lengths) < symbol_count:
        length = reader.read(4, output_position)
        if length:
            lengths.append(length)
        else:
            run = reader.read(8, output_position) + 1
            if len(lengths) + run > symbol_count:
                raise DecodeError("bad_table", output_position)
            lengths.extend([0] * run)
    check_code_table(lengths, output_position)
    return lengths


class HuffmanReader:
    def __init__(self, lengths):
        codes = huffman.canonical_codes(lengths)
        self.symbols = {(length, codes[symbol]): symbol
                        for symbol, length in enumerate(lengths) if length}
        self.maximum = max(lengths, default=0)

    def read(self, reader, output_position):
        if not self.symbols:
            raise DecodeError("bad_code", output_position)
        code = 0
        for width in range(1, self.maximum + 1):
            code = code * 2 + reader.read(1, output_position)
            symbol = self.symbols.get((width, code))
            if symbol is not None:
                return symbol
        raise DecodeError("bad_code", output_position)


def token_frequencies(tokens, offset_bits, length_bits):
    literal_lengths = [0] * (256 + (1 << length_bits))
    distances = [0] * (offset_bits + 1)
    for token in tokens:
        if isinstance(token, int):
            literal_lengths[token] += 1
        else:
            distance, length = token
            literal_lengths[256 + length - 3] += 1
            distances[(distance - 1).bit_length()] += 1
    return literal_lengths, distances


def write_lzh_tokens(writer, tokens, literal_lengths, distance_lengths):
    literal_codes = huffman.canonical_codes(literal_lengths)
    distance_codes = huffman.canonical_codes(distance_lengths)
    for token in tokens:
        if isinstance(token, int):
            writer.write(literal_codes[token], literal_lengths[token])
        else:
            distance, length = token
            symbol = 256 + length - 3
            writer.write(literal_codes[symbol], literal_lengths[symbol])
            offset = distance - 1
            slot = offset.bit_length()
            writer.write(distance_codes[slot], distance_lengths[slot])
            if slot >= 2:
                writer.write(offset - (1 << (slot - 1)), slot - 1)


def encode_lzh(tokens, parameters):
    literal_frequencies, distance_frequencies = token_frequencies(
        tokens, parameters.offset_bits, parameters.length_bits)
    literal_lengths, literal_halvings = huffman.limited_lengths(
        literal_frequencies, parameters.max_code_length)
    distance_lengths, distance_halvings = huffman.limited_lengths(
        distance_frequencies, parameters.max_code_length)
    fixed = BitWriter()
    fixed.write(0, 1)
    write_lzh_tokens(fixed, tokens, fixed_lengths(len(literal_lengths)),
                     fixed_lengths(len(distance_lengths)))
    fixed_bits = fixed.bit_count - 1
    dynamic = BitWriter()
    dynamic.write(1, 1)
    write_code_table(dynamic, literal_lengths)
    write_code_table(dynamic, distance_lengths)
    table_bits = dynamic.bit_count - 1
    write_lzh_tokens(dynamic, tokens, literal_lengths, distance_lengths)
    code_bits = dynamic.bit_count - 1 - table_bits
    use_fixed = fixed_bits <= table_bits + code_bits
    statistics = LzhStatistics(
        mode="fixed" if use_fixed else "dynamic",
        fixed_bits=fixed_bits, table_bits=table_bits, code_bits=code_bits,
        halvings=literal_halvings + distance_halvings,
        litlen_used=sum(length > 0 for length in literal_lengths),
        litlen_max=max(literal_lengths),
        offset_used=sum(length > 0 for length in distance_lengths),
        offset_max=max(distance_lengths), slots=distance_frequencies)
    return (fixed if use_fixed else dynamic).finish(), statistics


def decode_lzh(payload, original_size, offset_bits, length_bits):
    reader = BitReader(payload)
    literal_count = 256 + (1 << length_bits)
    distance_count = offset_bits + 1
    if reader.read(1):
        literal_lengths = read_code_table(reader, literal_count, 0)
        distance_lengths = read_code_table(reader, distance_count, 0)
    else:
        literal_lengths = fixed_lengths(literal_count)
        distance_lengths = fixed_lengths(distance_count)
    literal_table = HuffmanReader(literal_lengths)
    distance_table = HuffmanReader(distance_lengths)
    output = bytearray()
    while len(output) < original_size:
        symbol = literal_table.read(reader, len(output))
        if symbol < 256:
            output.append(symbol)
        else:
            length = symbol - 253
            slot = distance_table.read(reader, len(output))
            if slot >= 2:
                offset = (1 << (slot - 1)) + reader.read(slot - 1, len(output))
            else:
                offset = slot
            lz77.copy_match(output, offset + 1, length, original_size)
    return bytes(output)


def decode_payload(method, payload, original_size, offset_bits, length_bits):
    if method == 0:
        return decode_store(payload, original_size)
    if method == 1:
        return lzw.decode(payload, original_size)
    if method == 2:
        return decode_lz77(payload, original_size, offset_bits, length_bits)
    if method == 3:
        return decode_lzh(payload, original_size, offset_bits, length_bits)
    if method == 4:
        return arith_coder.decode(payload, original_size)
    raise ValueError("unsupported method cannot be decoded")


def encode_file(name, data, parameters):
    tokens = lz77.tokenize(data, parameters.offset_bits, parameters.length_bits)
    lzw_payload, lzw_stats = lzw.encode(data)
    lz77_payload = encode_lz77(tokens, parameters.offset_bits, parameters.length_bits)
    lzh_payload, lzh_stats = encode_lzh(tokens, parameters)
    arith_payload, arith_stats = arith_coder.encode(data)
    payloads = [data, lzw_payload, lz77_payload, lzh_payload, arith_payload]
    best = min(range(len(METHODS)), key=lambda method: len(payloads[method]))
    matches = [token for token in tokens if not isinstance(token, int)]
    lz77_stats = LzStatistics(
        tokens=len(tokens), literals=len(tokens) - len(matches),
        matches=len(matches), matched=sum(length for _, length in matches),
        longest=max((length for _, length in matches), default=0),
        farthest=max((distance for distance, _ in matches), default=0))
    return Encoding(name, data, payloads, best, lzw_stats, lz77_stats,
                    lzh_stats, arith_stats)


def build_archive(encodings, parameters):
    archive = bytearray(b"TXAR")
    archive.extend((parameters.offset_bits, parameters.length_bits))
    archive.extend(len(encodings).to_bytes(2, "big"))
    for encoding in encodings:
        name = encoding.name.encode("ascii")
        header = bytearray((len(name),))
        header.extend(name)
        header.append(encoding.best)
        header.extend(len(encoding.data).to_bytes(4, "big"))
        header.extend(len(encoding.payload).to_bytes(4, "big"))
        header.extend(adler32(encoding.data).to_bytes(4, "big"))
        header.append(sum(header) % 256)
        archive.extend(header)
        archive.extend(encoding.payload)
    return bytes(archive)


def read_entry_header(archive, number, position):
    name_length = archive[position]
    name_bytes = archive[position + 1:position + 1 + name_length]
    cursor = position + 1 + name_length
    start = position + 15 + name_length
    original = int.from_bytes(archive[cursor + 1:cursor + 5], "big")
    compressed = int.from_bytes(archive[cursor + 5:cursor + 9], "big")
    checksum = int.from_bytes(archive[cursor + 9:cursor + 13], "big")
    valid_name = 1 <= name_length <= 32 and all(byte in NAME_BYTES
                                              for byte in name_bytes)
    valid_check = sum(archive[position:start - 1]) % 256 == archive[start - 1]
    valid = valid_name and valid_check
    return Entry(number, position, valid_header=valid,
                 name=name_bytes.decode("ascii") if valid else "",
                 method=archive[cursor], original=original,
                 compressed=compressed, checksum=checksum,
                 start=start, end=start + compressed)


def examine_payload(entry, archive, offset_bits, length_bits):
    try:
        entry.data = decode_payload(entry.method, archive[entry.start:entry.end],
                                    entry.original, offset_bits, length_bits)
    except DecodeError as error:
        entry.status = "error"
        entry.error = error
        return
    entry.computed = adler32(entry.data)
    if entry.computed == entry.checksum:
        entry.status = "ok"
        return
    repair = repair_one_byte(entry.data, entry.checksum, entry.computed)
    if repair is None:
        entry.status = "checksum"
    else:
        entry.data, entry.repair = repair
        entry.status = "repaired"


def parse_archive(archive):
    result = ParsedArchive(len(archive))
    if len(archive) < 8 or archive[:4] != b"TXAR":
        result.error = "bad_magic"
        return result
    result.offset_bits = archive[4]
    result.length_bits = archive[5]
    if not (6 <= result.offset_bits <= 12 and 2 <= result.length_bits <= 5):
        result.error = "bad_params"
        return result
    result.declared = int.from_bytes(archive[6:8], "big")
    position = 8
    for number in range(1, result.declared + 1):
        if position >= len(archive) or position + 15 + archive[position] > len(archive):
            result.entries.append(Entry(number, position, status="truncated"))
            result.stopped = True
            break
        entry = read_entry_header(archive, number, position)
        result.entries.append(entry)
        if not entry.valid_header:
            entry.status = "bad_header"
            position = entry.end
            if position > len(archive):
                result.stopped = True
                break
            continue
        if entry.end > len(archive):
            entry.status = "truncated"
            result.stopped = True
            break
        if entry.method >= len(METHODS):
            entry.status = "unsupported"
        else:
            examine_payload(entry, archive, result.offset_bits, result.length_bits)
        position = entry.end
    if not result.stopped:
        result.trailing = len(archive) - position
    return result


def verify_archive(archive, originals):
    parsed = parse_archive(archive)
    verified = sum(entry.status == "ok" and entry.data == original
                   for entry, original in zip(parsed.entries, originals))
    return len(parsed.entries), verified


def sizes_report(encodings, parameters, archive, examined, verified):
    lines = [f"params offset_bits {parameters.offset_bits} "
             f"length_bits {parameters.length_bits} "
             f"window {1 << parameters.offset_bits} "
             f"lookahead {(1 << parameters.length_bits) + 2} "
             f"max_code_length {parameters.max_code_length}"]
    totals = [0] * len(METHODS)
    chosen = [0] * len(METHODS)
    original_total = 0
    best_total = 0
    for encoding in encodings:
        original = len(encoding.data)
        original_total += original
        chosen[encoding.best] += 1
        best_total += len(encoding.payload)
        fields = [f"file {encoding.name} original {original}"]
        for method, name in enumerate(METHODS):
            compressed = len(encoding.payloads[method])
            totals[method] += compressed
            fields.append(f"{name} {compressed} {ratio(compressed, original)}")
        fields.append(f"best {METHODS[encoding.best]}")
        lines.append(" ".join(fields))
    fields = [f"total original {original_total}"]
    fields.extend(f"{name} {total} {ratio(total, original_total)}"
                  for name, total in zip(METHODS, totals))
    fields.append(f"best {best_total} {ratio(best_total, original_total)}")
    lines.append(" ".join(fields))
    lines.append("chosen " + " ".join(f"{name} {count}"
                                      for name, count in zip(METHODS, chosen)))
    lines.append(f"archive bytes {len(archive)} entries {len(encodings)} "
                 f"ratio {ratio(len(archive), original_total)}")
    lines.append(f"verify entries {examined} ok {verified}")
    return lines


def analysis_report(encodings):
    lines = []
    for encoding in encodings:
        name = encoding.name
        zw = encoding.lzw_stats
        widths = " ".join(map(str, zw.widths))
        lines.append(f"lzw {name} codes {zw.codes} clears {zw.clears} "
                     f"widths {widths} longest {zw.longest}")
        z = encoding.lz77_stats
        lines.append(f"lz77 {name} tokens {z.tokens} literals {z.literals} "
                     f"matches {z.matches} matched {z.matched} "
                     f"longest {z.longest} farthest {z.farthest}")
        zh = encoding.lzh_stats
        lines.append(f"lzh {name} mode {zh.mode} fixed_bits {zh.fixed_bits} "
                     f"table_bits {zh.table_bits} code_bits {zh.code_bits} "
                     f"halvings {zh.halvings} litlen_used {zh.litlen_used} "
                     f"litlen_max {zh.litlen_max} offset_used {zh.offset_used} "
                     f"offset_max {zh.offset_max}")
        lines.append(f"slots {name} " + " ".join(map(str, zh.slots)))
        arithmetic = encoding.arith_stats
        lines.append(f"arith {name} bits {arithmetic.bits} "
                     f"contexts {arithmetic.contexts} rescales {arithmetic.rescales}")
    return lines


def listing_report(parsed):
    if parsed.error:
        return [f"archive bytes {parsed.size} error {parsed.error}"]
    lines = [f"archive bytes {parsed.size} offset_bits {parsed.offset_bits} "
             f"length_bits {parsed.length_bits} entries {parsed.declared}"]
    totals = [[0, 0, 0] for _ in METHODS]
    listed = 0
    for entry in parsed.entries:
        prefix = f"entry {entry.number} offset {entry.offset}"
        if not entry.valid_header:
            suffix = "bad_header" if entry.status == "bad_header" else "truncated header"
            lines.append(f"{prefix} {suffix}")
            continue
        listed += 1
        lines.append(f"{prefix} method {method_name(entry.method)} "
                     f"original {entry.original} compressed {entry.compressed} "
                     f"ratio {ratio(entry.compressed, entry.original)} "
                     f"adler {entry.checksum:08x} name {entry.name}")
        if entry.method < len(METHODS):
            values = totals[entry.method]
            values[0] += 1
            values[1] += entry.original
            values[2] += entry.compressed
    for method, (count, original, compressed) in zip(METHODS, totals):
        lines.append(f"method {method} entries {count} original {original} "
                     f"compressed {compressed} ratio {ratio(compressed, original)}")
    state = "truncated" if parsed.stopped else "complete"
    lines.append(f"end listed {listed} of {parsed.declared} stop {state} "
                 f"trailing {parsed.trailing}")
    return lines


def entry_test_line(entry, archive_size):
    prefix = f"entry {entry.number} offset {entry.offset}"
    if not entry.valid_header:
        status = "bad_header" if entry.status == "bad_header" else "truncated header"
        return f"{prefix} status {status}"
    line = (f"{prefix} name {entry.name} method {method_name(entry.method)} "
            f"status {entry.status}")
    if entry.status == "repaired":
        position, before, after = entry.repair
        line += f" byte {position} from {before} to {after}"
    elif entry.status == "checksum":
        line += f" stored {entry.checksum:08x} computed {entry.computed:08x}"
    elif entry.status == "error":
        line += f" {entry.error.kind} at {entry.error.position}"
    elif entry.status == "truncated":
        line += f" payload have {archive_size - entry.start} need {entry.compressed}"
    return line


def test_report(parsed, salvaged, salvage_archive, verified):
    if parsed.error:
        lines = [f"archive error {parsed.error}"]
    else:
        lines = [entry_test_line(entry, parsed.size) for entry in parsed.entries]
        counts = {status: 0 for status in STATUSES}
        for entry in parsed.entries:
            counts[entry.status] += 1
        summary = f"summary entries {parsed.declared} checked {len(parsed.entries)}"
        summary += " " + " ".join(f"{status} {counts[status]}" for status in STATUSES)
        summary += (f" missing {parsed.declared - len(parsed.entries)} "
                    f"trailing {parsed.trailing}")
        lines.append(summary)
    for entry, encoding in zip(parsed.intact, salvaged):
        lines.append(f"salvage {entry.name} method {METHODS[encoding.best]} "
                     f"compressed {len(encoding.payload)} "
                     f"was {method_name(entry.method)} {entry.compressed}")
    total_original = sum(len(encoding.data) for encoding in salvaged)
    lines.append(f"salvaged entries {len(salvaged)} bytes {len(salvage_archive)} "
                 f"original {total_original} verified {verified}")
    return lines


def text_lines(data):
    return data.split(b"\n")[:-1]


def extraction_report(entries):
    lines = []
    for entry in entries:
        contents = text_lines(entry.data)
        words = sum(bool(word) for line in contents for word in line.split(b" "))
        longest = max(map(len, contents), default=0)
        lines.append(f"file {entry.name} bytes {len(entry.data)} "
                     f"lines {len(contents)} words {words} longest {longest}")
        lines.extend(line.decode("ascii") for line in contents)
    return lines


def edit_list(old, new):
    """Compute suffix LCS lengths with two rows and retain deletion decisions."""
    old_count = len(old)
    new_count = len(new)
    below = array("I", [0]) * (new_count + 1)
    current = array("I", [0]) * (new_count + 1)
    decisions = [None] * old_count
    for i in range(old_count - 1, -1, -1):
        deletions = bytearray((new_count + 7) // 8)
        right = 0
        for j in range(new_count - 1, -1, -1):
            if old[i] == new[j]:
                length = below[j + 1] + 1
            elif below[j] >= right:
                length = below[j]
                deletions[j // 8] |= 1 << (j % 8)
            else:
                length = right
            current[j] = length
            right = length
        decisions[i] = deletions
        below, current = current, below
    edits = []
    i = j = 0
    while i < old_count or j < new_count:
        if i < old_count and j < new_count and old[i] == new[j]:
            i += 1
            j += 1
        elif j == new_count or (i < old_count and
                               decisions[i][j // 8] & (1 << (j % 8))):
            edits.append(("-", i + 1, old[i]))
            i += 1
        else:
            edits.append(("+", j + 1, new[j]))
            j += 1
    return edits


def comparison_report(entries, files):
    manifest = dict(files)
    seen = set()
    lines = []
    for entry in entries:
        name = entry.name
        seen.add(name)
        if name not in manifest:
            lines.append(f"archive_only {name}")
            continue
        old = text_lines(entry.data)
        new = text_lines(manifest[name])
        if old == new:
            lines.append(f"same {name} lines {len(old)}")
            continue
        first = 0
        while first < min(len(old), len(new)) and old[first] == new[first]:
            first += 1
        edits = edit_list(old, new)
        removed = sum(sign == "-" for sign, _, _ in edits)
        added = len(edits) - removed
        lines.append(f"differs {name} first_line {first + 1} "
                     f"archive_lines {len(old)} manifest_lines {len(new)} "
                     f"removed {removed} added {added}")
        lines.extend(f"{sign}{number}:{content.decode('ascii')}"
                     for sign, number, content in edits)
    lines.extend(f"new {name}" for name, _ in files if name not in seen)
    return lines


def salvage_archive(parsed, parameters):
    if parsed.error:
        salvage_parameters = parameters
    else:
        salvage_parameters = Parameters(parsed.offset_bits, parsed.length_bits,
                                        parameters.max_code_length)
    encodings = [encode_file(entry.name, entry.data, salvage_parameters)
                 for entry in parsed.intact]
    archive = build_archive(encodings, salvage_parameters)
    _, verified = verify_archive(archive, [encoding.data for encoding in encodings])
    return archive, encodings, verified


def write_lines(path, lines):
    path.write_bytes("".join(line + "\n" for line in lines).encode("ascii"))


def write_hex(path, archive):
    write_lines(path, (archive[position:position + 32].hex()
                       for position in range(0, len(archive), 32)))


def main():
    parameters, files, supplied_archive = read_inputs(Path("input"))
    encodings = [encode_file(name, data, parameters) for name, data in files]
    created = build_archive(encodings, parameters)
    examined, verified = verify_archive(created, [data for _, data in files])
    parsed = parse_archive(supplied_archive)
    salvaged, salvage_encodings, salvage_verified = salvage_archive(parsed, parameters)
    output = Path("output")
    output.mkdir(parents=True, exist_ok=True)
    write_lines(output / "sizes.txt",
                sizes_report(encodings, parameters, created, examined, verified))
    write_lines(output / "analysis.txt", analysis_report(encodings))
    write_hex(output / "archive.hex", created)
    write_lines(output / "listing.txt", listing_report(parsed))
    write_lines(output / "test_report.txt",
                test_report(parsed, salvage_encodings, salvaged, salvage_verified))
    write_lines(output / "extracted.txt", extraction_report(parsed.intact))
    write_lines(output / "compare.txt", comparison_report(parsed.intact, files))
    write_hex(output / "salvaged.hex", salvaged)


if __name__ == "__main__":
    main()
