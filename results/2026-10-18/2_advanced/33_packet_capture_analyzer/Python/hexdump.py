import re


HEADER_PREFIX = "PACKET "
DATA_LINE = re.compile(r"[0-9a-f]{4}  [0-9a-f]{2}(?: [0-9a-f]{2}){0,15}")
BYTES_PER_ROW = 16
HEX_PART_WIDTH = 47


class Packet:
    def __init__(self, number, time, length):
        self.number = number
        self.time = time
        self.length = length
        self.data = b""
        self.error = None
        self.layers = []
        self.fields = {}
        self.remaining = b""

    def values(self, name):
        return self.fields.get(name, [])

    def value(self, name):
        values = self.fields.get(name)
        return values[0] if values else None

    def exists(self, name):
        return name in self.fields

    def set(self, name, value):
        self.fields[name] = [value]


def read_lines(path):
    with open(path) as handle:
        return handle.read().split("\n")[:-1]


def load_dump(packet, data_lines):
    data = bytearray()
    for line_number, line in data_lines:
        if DATA_LINE.fullmatch(line) is None:
            packet.error = f"dump: bad line {line_number}"
            return
        if int(line[:4], 16) != len(data):
            packet.error = f"dump: offset mismatch at line {line_number}"
            return
        data.extend(bytes.fromhex(line[6:]))
    if len(data) != packet.length:
        packet.error = f"dump: length mismatch (header {packet.length}, data {len(data)})"
        return
    packet.data = bytes(data)


def read_capture(path):
    packets = []
    data_lines = []
    for line_number, line in enumerate(read_lines(path), 1):
        if line.startswith(HEADER_PREFIX):
            _, number, time, length = line.split(" ")
            packets.append(Packet(int(number), int(time), int(length)))
            data_lines.append([])
        elif line:
            data_lines[-1].append((line_number, line))
    for packet, lines in zip(packets, data_lines):
        load_dump(packet, lines)
    return packets


def hex_dump_lines(data):
    lines = []
    for offset in range(0, len(data), BYTES_PER_ROW):
        piece = data[offset:offset + BYTES_PER_ROW]
        hex_part = " ".join(f"{byte:02x}" for byte in piece)
        text = "".join(chr(byte) if 32 <= byte <= 126 else "." for byte in piece)
        lines.append(f"{offset:04x}  {hex_part:<{HEX_PART_WIDTH}}  |{text}|")
    return lines
