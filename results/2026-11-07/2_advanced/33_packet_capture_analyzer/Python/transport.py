from link_network import Layer, Malformed, checksum_status, read_int


PROTOCOL_TCP = 6
PROTOCOL_UDP = 17
ICMP_HEADER_LENGTH = 8
UDP_HEADER_LENGTH = 8
TCP_MIN_HEADER = 20
ICMP_ECHO_TYPES = (0, 8)
DNS_PORT = 53
FLAG_FIELDS = ("fin", "syn", "rst", "psh", "ack", "urg")
ACK_BIT = 16
OPTION_LENGTHS = {2: (4,), 3: (3,), 4: (2,), 5: (10, 18, 26, 34), 8: (10,)}


def pseudo_header(source, destination, protocol, length):
    return (
        source.to_bytes(4, "big")
        + destination.to_bytes(4, "big")
        + bytes((0, protocol))
        + length.to_bytes(2, "big")
    )


def dissect_icmp(message):
    if len(message) < ICMP_HEADER_LENGTH:
        raise Malformed("icmp: truncated")
    layer = Layer()
    icmp_type = message[0]
    layer.set("icmp.type", icmp_type)
    layer.set("icmp.code", message[1])
    layer.set("icmp.checksum", read_int(message, 2, 2))
    layer.set("icmp.checksum.status", checksum_status(message))
    if icmp_type in ICMP_ECHO_TYPES:
        layer.set("icmp.id", read_int(message, 4, 2))
        layer.set("icmp.seq", read_int(message, 6, 2))
    layer.remaining = message[ICMP_HEADER_LENGTH:]
    return layer


def dissect_udp(datagram, source, destination):
    if len(datagram) < UDP_HEADER_LENGTH:
        raise Malformed("udp: truncated")
    length = read_int(datagram, 4, 2)
    if length < UDP_HEADER_LENGTH or length > len(datagram):
        raise Malformed(f"udp: bad length {length}")
    source_port = read_int(datagram, 0, 2)
    destination_port = read_int(datagram, 2, 2)
    checksum = read_int(datagram, 6, 2)
    if checksum == 0:
        status = "none"
    else:
        covered = pseudo_header(source, destination, PROTOCOL_UDP, length) + datagram[:length]
        status = checksum_status(covered)
    layer = Layer()
    layer.set("udp.srcport", source_port)
    layer.set("udp.dstport", destination_port)
    layer.set("udp.length", length)
    layer.set("udp.checksum", checksum)
    layer.set("udp.checksum.status", status)
    payload = datagram[UDP_HEADER_LENGTH:length]
    if DNS_PORT in (source_port, destination_port):
        layer.forward("dns", payload)
    else:
        layer.remaining = payload
    return layer


def option_text(kind, length, body, layer):
    if kind == 2:
        mss = read_int(body, 0, 2)
        layer.set("tcp.options.mss", mss)
        return f"MSS {mss}"
    if kind == 3:
        layer.set("tcp.options.wscale", body[0])
        return f"WS {body[0]}"
    if kind == 4:
        return "SACK_PERM"
    if kind == 5:
        blocks = [
            f" {read_int(body, start, 4)}-{read_int(body, start + 4, 4)}"
            for start in range(0, len(body), 8)
        ]
        return "SACK" + "".join(blocks)
    if kind == 8:
        return f"TS {read_int(body, 0, 4)} {read_int(body, 4, 4)}"
    return f"kind {kind} len {length}"


def parse_options(options, layer):
    index = 0
    while index < len(options):
        kind = options[index]
        if kind == 0:
            layer.add("tcp.option", "EOL")
            return
        if kind == 1:
            layer.add("tcp.option", "NOP")
            index += 1
            continue
        length = options[index + 1] if index + 1 < len(options) else 0
        if (
            length < 2
            or index + length > len(options)
            or (kind in OPTION_LENGTHS and length not in OPTION_LENGTHS[kind])
        ):
            layer.set("tcp.options.malformed", True)
            return
        body = options[index + 2:index + length]
        layer.add("tcp.option", option_text(kind, length, body, layer))
        index += length


def dissect_tcp(segment, source, destination):
    if len(segment) < TCP_MIN_HEADER:
        raise Malformed("tcp: truncated header")
    header_length = segment[12] // 16 * 4
    if header_length < TCP_MIN_HEADER:
        raise Malformed(f"tcp: bad header length {header_length}")
    if header_length > len(segment):
        raise Malformed("tcp: truncated header")
    flags = segment[13]
    covered = pseudo_header(source, destination, PROTOCOL_TCP, len(segment)) + segment
    layer = Layer()
    layer.set("tcp.srcport", read_int(segment, 0, 2))
    layer.set("tcp.dstport", read_int(segment, 2, 2))
    layer.set("tcp.seq_raw", read_int(segment, 4, 4))
    layer.set("tcp.hdr_len", header_length)
    layer.set("tcp.flags", flags)
    for bit, name in enumerate(FLAG_FIELDS):
        layer.set("tcp.flags." + name, flags >> bit & 1)
    layer.set("tcp.window", read_int(segment, 14, 2))
    layer.set("tcp.checksum", read_int(segment, 16, 2))
    layer.set("tcp.checksum.status", checksum_status(covered))
    layer.set("tcp.urgent", read_int(segment, 18, 2))
    layer.set("tcp.len", len(segment) - header_length)
    if flags & ACK_BIT:
        layer.set("tcp.ack_raw", read_int(segment, 8, 4))
    parse_options(segment[TCP_MIN_HEADER:header_length], layer)
    layer.remaining = segment[header_length:]
    return layer
