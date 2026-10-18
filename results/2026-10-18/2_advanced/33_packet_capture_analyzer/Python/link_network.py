ETHERNET_HEADER_LENGTH = 14
ETHERTYPE_ARP = 0x0806
ETHERTYPE_IPV4 = 0x0800
ARP_LENGTH = 28
IPV4_MIN_HEADER = 20
IP_PROTOCOLS = {1: "icmp", 17: "udp", 6: "tcp"}


class Malformed(Exception):
    pass


class Layer:
    def __init__(self):
        self.fields = {}
        self.next_layer = None
        self.payload = b""
        self.remaining = b""

    def set(self, name, value):
        self.fields[name] = [value]

    def add(self, name, value):
        self.fields.setdefault(name, []).append(value)

    def forward(self, next_layer, payload):
        self.next_layer = next_layer
        self.payload = payload


def read_int(data, index, size):
    return int.from_bytes(data[index:index + size], "big")


def checksum_status(data):
    if len(data) % 2 == 1:
        data += b"\x00"
    total = sum(read_int(data, index, 2) for index in range(0, len(data), 2))
    while total > 65535:
        total = total % 65536 + total // 65536
    return "good" if total == 65535 else "bad"


def mac_notation(value):
    return ":".join(f"{byte:02x}" for byte in value.to_bytes(6, "big"))


def ipv4_notation(value):
    return ".".join(str(byte) for byte in value.to_bytes(4, "big"))


def dissect_ethernet(frame):
    if len(frame) < ETHERNET_HEADER_LENGTH:
        raise Malformed("eth: truncated")
    layer = Layer()
    ether_type = read_int(frame, 12, 2)
    layer.set("eth.dst", read_int(frame, 0, 6))
    layer.set("eth.src", read_int(frame, 6, 6))
    layer.set("eth.type", ether_type)
    payload = frame[ETHERNET_HEADER_LENGTH:]
    if ether_type == ETHERTYPE_ARP:
        layer.forward("arp", payload)
    elif ether_type == ETHERTYPE_IPV4:
        layer.forward("ip", payload)
    else:
        layer.remaining = payload
    return layer


def dissect_arp(message):
    if len(message) < ARP_LENGTH:
        raise Malformed("arp: truncated")
    if (
        read_int(message, 0, 2) != 1
        or read_int(message, 2, 2) != ETHERTYPE_IPV4
        or message[4] != 6
        or message[5] != 4
    ):
        raise Malformed("arp: unsupported format")
    layer = Layer()
    layer.set("arp.opcode", read_int(message, 6, 2))
    layer.set("arp.src.hw", read_int(message, 8, 6))
    layer.set("arp.src.ip", read_int(message, 14, 4))
    layer.set("arp.dst.hw", read_int(message, 18, 6))
    layer.set("arp.dst.ip", read_int(message, 24, 4))
    return layer


def dissect_ipv4(datagram):
    available = len(datagram)
    if available < IPV4_MIN_HEADER:
        raise Malformed("ip: truncated header")
    version = datagram[0] // 16
    if version != 4:
        raise Malformed(f"ip: bad version {version}")
    header_length = datagram[0] % 16 * 4
    if header_length < IPV4_MIN_HEADER:
        raise Malformed(f"ip: bad header length {header_length}")
    if available < header_length:
        raise Malformed("ip: truncated header")
    total_length = read_int(datagram, 2, 2)
    if total_length < header_length:
        raise Malformed(f"ip: bad total length {total_length}")
    if total_length > available:
        raise Malformed(f"ip: truncated (total length {total_length}, available {available})")
    flags = read_int(datagram, 6, 2)
    more_fragments = flags // 8192 % 2
    fragment_offset = flags % 8192 * 8
    protocol = datagram[9]
    layer = Layer()
    layer.set("ip.hdr_len", header_length)
    layer.set("ip.tos", datagram[1])
    layer.set("ip.len", total_length)
    layer.set("ip.id", read_int(datagram, 4, 2))
    layer.set("ip.flags.df", flags // 16384 % 2)
    layer.set("ip.flags.mf", more_fragments)
    layer.set("ip.frag_offset", fragment_offset)
    layer.set("ip.ttl", datagram[8])
    layer.set("ip.proto", protocol)
    layer.set("ip.checksum", read_int(datagram, 10, 2))
    layer.set("ip.checksum.status", checksum_status(datagram[:header_length]))
    layer.set("ip.src", read_int(datagram, 12, 4))
    layer.set("ip.dst", read_int(datagram, 16, 4))
    payload = datagram[header_length:total_length]
    if more_fragments == 1 or fragment_offset != 0:
        layer.set("ip.fragment", True)
        layer.remaining = payload
    elif protocol in IP_PROTOCOLS:
        layer.forward(IP_PROTOCOLS[protocol], payload)
    else:
        layer.remaining = payload
    return layer
