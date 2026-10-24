import os
import re
import string

from dns_app import dissect_dns, rcode_name, type_name
from flows import MARKS, StreamTracker, build_conversations, build_endpoints
from hexdump import hex_dump_lines, read_capture, read_lines
from link_network import (
    Malformed, dissect_arp, dissect_ethernet, dissect_ipv4, ipv4_notation, mac_notation,
)
from transport import dissect_icmp, dissect_tcp, dissect_udp


INPUT_DIR = "input"
OUTPUT_DIR = "output"
MICROSECONDS = 1000000
FIELDS = (
    ("frame.number", "integer"),
    ("frame.time", "integer"),
    ("frame.len", "integer"),
    ("frame.protocols", "string"),
    ("frame.malformed", "string"),
    ("frame.bad_checksum", "presence"),
    ("eth.dst", "mac"),
    ("eth.src", "mac"),
    ("eth.type", "hex4"),
    ("arp.opcode", "integer"),
    ("arp.src.hw", "mac"),
    ("arp.src.ip", "ipv4"),
    ("arp.dst.hw", "mac"),
    ("arp.dst.ip", "ipv4"),
    ("ip.hdr_len", "integer"),
    ("ip.tos", "hex2"),
    ("ip.len", "integer"),
    ("ip.id", "hex4"),
    ("ip.flags.df", "integer"),
    ("ip.flags.mf", "integer"),
    ("ip.frag_offset", "integer"),
    ("ip.ttl", "integer"),
    ("ip.proto", "integer"),
    ("ip.checksum", "hex4"),
    ("ip.checksum.status", "string"),
    ("ip.src", "ipv4"),
    ("ip.dst", "ipv4"),
    ("ip.fragment", "presence"),
    ("icmp.type", "integer"),
    ("icmp.code", "integer"),
    ("icmp.checksum", "hex4"),
    ("icmp.checksum.status", "string"),
    ("icmp.id", "integer"),
    ("icmp.seq", "integer"),
    ("udp.srcport", "integer"),
    ("udp.dstport", "integer"),
    ("udp.length", "integer"),
    ("udp.checksum", "hex4"),
    ("udp.checksum.status", "string"),
    ("tcp.srcport", "integer"),
    ("tcp.dstport", "integer"),
    ("tcp.stream", "integer"),
    ("tcp.seq", "integer"),
    ("tcp.seq_raw", "integer"),
    ("tcp.ack", "integer"),
    ("tcp.ack_raw", "integer"),
    ("tcp.hdr_len", "integer"),
    ("tcp.flags", "hex2"),
    ("tcp.flags.fin", "integer"),
    ("tcp.flags.syn", "integer"),
    ("tcp.flags.rst", "integer"),
    ("tcp.flags.psh", "integer"),
    ("tcp.flags.ack", "integer"),
    ("tcp.flags.urg", "integer"),
    ("tcp.window", "integer"),
    ("tcp.window.calc", "integer"),
    ("tcp.checksum", "hex4"),
    ("tcp.checksum.status", "string"),
    ("tcp.urgent", "integer"),
    ("tcp.option", "string"),
    ("tcp.options.mss", "integer"),
    ("tcp.options.wscale", "integer"),
    ("tcp.options.malformed", "presence"),
    ("tcp.len", "integer"),
    ("tcp.analysis.retransmission", "presence"),
    ("tcp.analysis.out_of_order", "presence"),
    ("tcp.analysis.lost_segment", "presence"),
    ("tcp.analysis.duplicate_ack", "presence"),
    ("dns.id", "hex4"),
    ("dns.flags", "hex4"),
    ("dns.flags.response", "integer"),
    ("dns.flags.opcode", "integer"),
    ("dns.flags.rcode", "integer"),
    ("dns.count.queries", "integer"),
    ("dns.count.answers", "integer"),
    ("dns.count.auth_rr", "integer"),
    ("dns.count.add_rr", "integer"),
    ("dns.qry.name", "string"),
    ("dns.qry.type", "integer"),
    ("dns.answer", "string"),
    ("dns.authority", "string"),
    ("dns.additional", "string"),
    ("dns.a", "ipv4"),
    ("data.len", "integer"),
)
FIELD_TYPES = dict(FIELDS)
ALIASES = {
    "eth.addr": ("mac", "eth.dst", "eth.src"),
    "ip.addr": ("ipv4", "ip.src", "ip.dst"),
    "udp.port": ("integer", "udp.srcport", "udp.dstport"),
    "tcp.port": ("integer", "tcp.srcport", "tcp.dstport"),
}
PROTOCOL_FIELDS = ("eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data")
PROTOCOL_LABELS = {
    "eth": "ETH", "arp": "ARP", "ip": "IPv4", "icmp": "ICMP",
    "udp": "UDP", "tcp": "TCP", "dns": "DNS",
}
CHECKSUM_LAYERS = (("ip", "IPv4"), ("icmp", "ICMP"), ("udp", "UDP"), ("tcp", "TCP"))
FLAG_NAMES = ("FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR")
MARK_LABELS = {
    "retransmission": "[TCP Retransmission] ",
    "out_of_order": "[TCP Out-Of-Order] ",
    "lost_segment": "[TCP Previous segment not captured] ",
}
TWO_CHARACTER_TOKENS = ("==", "!=", "<=", ">=", "&&", "||")
ONE_CHARACTER_TOKENS = "()!<>"
KEYWORDS = {"and": "&&", "or": "||", "not": "!"}
WORD_CHARACTERS = frozenset(string.ascii_letters + string.digits + "._:")
COMPARISONS = ("==", "!=", "<", ">", "<=", ">=")
EQUALITY_OPERATORS = ("==", "!=")
NUMBER_TYPES = ("integer", "hex2", "hex4")
DECIMAL_VALUE = re.compile(r"[0-9]{1,15}")
HEX_VALUE = re.compile(r"0x([0-9a-fA-F]{1,12})")
OCTET_VALUE = re.compile(r"[0-9]{1,3}")
MAC_PART = re.compile(r"[0-9a-fA-F]{2}")
HIERARCHY = (("eth", 0), ("arp", 2), ("ip", 2), ("icmp", 4), ("udp", 4), ("dns", 6), ("tcp", 4))
MALFORMED_LAYERS = ("eth", "arp", "ip", "icmp", "udp", "tcp", "dns")
RCODE_COUNT = 16
CONVERSATION_HEADER = (
    "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,"
    "packets_b_to_a,bytes_b_to_a,start,duration"
)
ENDPOINT_HEADER = "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"


def seconds(microseconds):
    return f"{microseconds // MICROSECONDS}.{microseconds % MICROSECONDS:06d}"


def optional(value):
    return "-" if value is None else str(value)


def notation(field_type, value):
    if field_type == "hex2":
        return f"0x{value:02x}"
    if field_type == "hex4":
        return f"0x{value:04x}"
    if field_type == "ipv4":
        return ipv4_notation(value)
    if field_type == "mac":
        return mac_notation(value)
    return str(value)


def shown(packet, name):
    return notation(FIELD_TYPES[name], packet.value(name))


def endpoint_text(endpoint):
    address, port = endpoint
    if port is None:
        return ipv4_notation(address)
    return f"{ipv4_notation(address)}:{port}"


def field_type_of(name):
    if name in FIELD_TYPES:
        return FIELD_TYPES[name]
    if name in ALIASES:
        return ALIASES[name][0]
    if name in PROTOCOL_FIELDS:
        return "presence"
    return None


def field_values(packet, name):
    if name in ALIASES:
        _, first, second = ALIASES[name]
        return packet.values(first) + packet.values(second)
    return packet.values(name)


def dissect_layer(packet, name, payload):
    if name == "eth":
        return dissect_ethernet(payload)
    if name == "arp":
        return dissect_arp(payload)
    if name == "ip":
        return dissect_ipv4(payload)
    if name == "icmp":
        return dissect_icmp(payload)
    if name == "udp":
        return dissect_udp(payload, packet.value("ip.src"), packet.value("ip.dst"))
    if name == "tcp":
        return dissect_tcp(payload, packet.value("ip.src"), packet.value("ip.dst"))
    return dissect_dns(payload)


def dissect_layers(packet):
    name = "eth"
    payload = packet.data
    while True:
        packet.layers.append(name)
        try:
            layer = dissect_layer(packet, name, payload)
        except Malformed as error:
            return str(error)
        packet.fields.update(layer.fields)
        if layer.next_layer is None:
            packet.remaining = layer.remaining
            return None
        name = layer.next_layer
        payload = layer.payload


def dissect(packet, base_time):
    reason = packet.error
    if reason is None:
        reason = dissect_layers(packet)
    if reason is None and packet.remaining:
        packet.layers.append("data")
        packet.set("data.len", len(packet.remaining))
    packet.set("frame.number", packet.number)
    packet.set("frame.time", packet.time - base_time)
    packet.set("frame.len", packet.length)
    if packet.layers:
        packet.set("frame.protocols", ":".join(packet.layers))
    if reason is not None:
        packet.set("frame.malformed", reason)
    if any(packet.value(layer + ".checksum.status") == "bad" for layer, _ in CHECKSUM_LAYERS):
        packet.set("frame.bad_checksum", True)


def addresses(packet):
    if packet.exists("ip.src"):
        return shown(packet, "ip.src"), shown(packet, "ip.dst")
    if packet.exists("eth.src"):
        return shown(packet, "eth.src"), shown(packet, "eth.dst")
    return "-", "-"


def protocol_label(packet):
    layers = [name for name in packet.layers if name != "data"]
    return PROTOCOL_LABELS[layers[-1]] if layers else "DUMP"


def arp_info(packet):
    opcode = packet.value("arp.opcode")
    if opcode == 1:
        return f"Who has {shown(packet, 'arp.dst.ip')}? Tell {shown(packet, 'arp.src.ip')}"
    if opcode == 2:
        return f"{shown(packet, 'arp.src.ip')} is at {shown(packet, 'arp.src.hw')}"
    return f"Opcode {opcode}"


def ipv4_info(packet):
    if not packet.exists("ip.fragment"):
        return f"Protocol {packet.value('ip.proto')}"
    text = f"Fragment id={shown(packet, 'ip.id')} off={packet.value('ip.frag_offset')}"
    if packet.value("ip.flags.mf") == 1:
        text += " MF"
    return text


def icmp_info(packet):
    icmp_type = packet.value("icmp.type")
    echo = f"id={packet.value('icmp.id')} seq={packet.value('icmp.seq')}"
    if icmp_type == 8:
        return "Echo request " + echo
    if icmp_type == 0:
        return "Echo reply " + echo
    return f"Type {icmp_type} code {packet.value('icmp.code')}"


def udp_info(packet):
    payload_length = packet.value("udp.length") - 8
    return f"{packet.value('udp.srcport')} -> {packet.value('udp.dstport')} Len={payload_length}"


def mark_notation(packet, duplicate_acks):
    if packet.exists("tcp.analysis.duplicate_ack"):
        original, count = duplicate_acks[packet.number]
        return f"[TCP Dup ACK {original}#{count}] "
    for mark, label in MARK_LABELS.items():
        if packet.exists("tcp.analysis." + mark):
            return label
    return ""


def flag_notation(flags):
    names = [name for bit, name in enumerate(FLAG_NAMES) if flags >> bit & 1]
    return ", ".join(names) if names else "<None>"


def option_summary(options):
    parts = []
    for option in options:
        words = option.split(" ")
        if words[0] == "MSS":
            parts.append(f" MSS={words[1]}")
        elif words[0] == "WS":
            parts.append(f" WS={2 ** int(words[1])}")
        elif words[0] == "SACK_PERM":
            parts.append(" SACK_PERM")
        elif words[0] == "TS":
            parts.append(f" TSval={words[1]} TSecr={words[2]}")
    return "".join(parts)


def tcp_info(packet, duplicate_acks):
    text = (
        mark_notation(packet, duplicate_acks)
        + f"{packet.value('tcp.srcport')} -> {packet.value('tcp.dstport')}"
        + f" [{flag_notation(packet.value('tcp.flags'))}] Seq={packet.value('tcp.seq')}"
    )
    if packet.value("tcp.flags.ack") == 1:
        text += f" Ack={packet.value('tcp.ack')}"
    text += f" Win={packet.value('tcp.window.calc')} Len={packet.value('tcp.len')}"
    return text + option_summary(packet.values("tcp.option"))


def dns_info(packet):
    parts = ["Response" if packet.value("dns.flags.response") == 1 else "Query"]
    parts.append(shown(packet, "dns.id"))
    rcode = packet.value("dns.flags.rcode")
    if rcode != 0:
        parts.append(rcode_name(rcode))
    for name, question_type in zip(packet.values("dns.qry.name"), packet.values("dns.qry.type")):
        parts.extend((type_name(question_type), name))
    for record in packet.values("dns.answer"):
        _, record_type, _, _, rdata = record.split(" ", 4)
        parts.extend((record_type, rdata))
    return " ".join(parts)


def basic_info(packet, protocol, duplicate_acks):
    if packet.exists("frame.malformed"):
        return packet.value("frame.malformed")
    if protocol == "ETH":
        return "EtherType " + shown(packet, "eth.type")
    if protocol == "ARP":
        return arp_info(packet)
    if protocol == "IPv4":
        return ipv4_info(packet)
    if protocol == "ICMP":
        return icmp_info(packet)
    if protocol == "UDP":
        return udp_info(packet)
    if protocol == "TCP":
        return tcp_info(packet, duplicate_acks)
    return dns_info(packet)


def annotations(packet):
    text = " [bad TCP options]" if packet.exists("tcp.options.malformed") else ""
    for layer, label in CHECKSUM_LAYERS:
        if packet.value(layer + ".checksum.status") == "bad":
            text += f" [bad {label} checksum]"
    return text


def summary_line(packet, duplicate_acks):
    source, destination = addresses(packet)
    protocol = protocol_label(packet)
    info = basic_info(packet, protocol, duplicate_acks) + annotations(packet)
    time = seconds(packet.value("frame.time"))
    return f"{packet.number} {time} {source} -> {destination} {protocol} {packet.length} {info}"


class FilterError(Exception):
    pass


class Token:
    def __init__(self, kind, text, column):
        self.kind = kind
        self.text = text
        self.column = column


class FilterNode:
    def __init__(self, kind, left=None, right=None, field=None, operator=None, value=None):
        self.kind = kind
        self.left = left
        self.right = right
        self.field = field
        self.operator = operator
        self.value = value


def tokenize(expression):
    tokens = []
    index = 0
    while index < len(expression):
        character = expression[index]
        column = index + 1
        pair = expression[index:index + 2]
        if character == " ":
            index += 1
        elif pair in TWO_CHARACTER_TOKENS:
            tokens.append(Token(pair, pair, column))
            index += 2
        elif character in ONE_CHARACTER_TOKENS:
            tokens.append(Token(character, character, column))
            index += 1
        elif character == '"':
            end = expression.find('"', index + 1)
            if end < 0:
                raise FilterError(f"unterminated string at column {column}")
            tokens.append(Token("string", expression[index:end + 1], column))
            index = end + 1
        elif character in WORD_CHARACTERS:
            end = index
            while end < len(expression) and expression[end] in WORD_CHARACTERS:
                end += 1
            word = expression[index:end]
            tokens.append(Token(KEYWORDS.get(word, "word"), word, column))
            index = end
        else:
            raise FilterError(f"invalid character '{character}' at column {column}")
    return tokens


def parse_number(text):
    if DECIMAL_VALUE.fullmatch(text):
        return int(text)
    match = HEX_VALUE.fullmatch(text)
    if match:
        return int(match.group(1), 16)
    return None


def parse_ipv4(text):
    parts = text.split(".")
    if len(parts) != 4:
        return None
    address = 0
    for part in parts:
        if not OCTET_VALUE.fullmatch(part) or int(part) > 255:
            return None
        address = address * 256 + int(part)
    return address


def parse_mac(text):
    parts = text.split(":")
    if len(parts) != 6:
        return None
    address = 0
    for part in parts:
        if not MAC_PART.fullmatch(part):
            return None
        address = address * 256 + int(part, 16)
    return address


def convert_value(field_type, token):
    if field_type == "string":
        return token.text[1:-1] if token.kind == "string" else None
    if token.kind != "word":
        return None
    if field_type in NUMBER_TYPES:
        return parse_number(token.text)
    if field_type == "ipv4":
        return parse_ipv4(token.text)
    return parse_mac(token.text)


def unexpected(token):
    return FilterError(f"unexpected '{token.text}' at column {token.column}")


class FilterParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def next_kind(self):
        if self.position < len(self.tokens):
            return self.tokens[self.position].kind
        return None

    def take(self):
        if self.position >= len(self.tokens):
            raise FilterError("unexpected end of filter")
        token = self.tokens[self.position]
        self.position += 1
        return token

    def parse(self):
        node = self.expression()
        if self.position < len(self.tokens):
            raise unexpected(self.tokens[self.position])
        return node

    def expression(self):
        node = self.product()
        while self.next_kind() == "||":
            self.take()
            node = FilterNode("or", node, self.product())
        return node

    def product(self):
        node = self.negation()
        while self.next_kind() == "&&":
            self.take()
            node = FilterNode("and", node, self.negation())
        return node

    def negation(self):
        if self.next_kind() == "!":
            self.take()
            return FilterNode("not", self.negation())
        token = self.take()
        if token.kind == "(":
            node = self.expression()
            closing = self.take()
            if closing.kind != ")":
                raise unexpected(closing)
            return node
        if token.kind == "word":
            return self.test(token.text)
        raise unexpected(token)

    def test(self, name):
        field_type = field_type_of(name)
        if field_type is None:
            raise FilterError(f"unknown field {name}")
        if self.next_kind() not in COMPARISONS:
            return FilterNode("exists", field=name)
        operator = self.take().kind
        if field_type == "presence" or (
            field_type == "string" and operator not in EQUALITY_OPERATORS
        ):
            raise FilterError(f"operator {operator} not allowed for {name}")
        token = self.take()
        if token.kind not in ("word", "string"):
            raise unexpected(token)
        value = convert_value(field_type, token)
        if value is None:
            raise FilterError(f"invalid value {token.text} for {name}")
        return FilterNode("compare", field=name, operator=operator, value=value)


def compare(left, operator, right):
    if operator == "==":
        return left == right
    if operator == "<":
        return left < right
    if operator == ">":
        return left > right
    if operator == "<=":
        return left <= right
    return left >= right


def evaluate(node, packet):
    if node.kind == "or":
        return evaluate(node.left, packet) or evaluate(node.right, packet)
    if node.kind == "and":
        return evaluate(node.left, packet) and evaluate(node.right, packet)
    if node.kind == "not":
        return not evaluate(node.left, packet)
    if node.kind == "exists":
        if node.field in PROTOCOL_FIELDS:
            return node.field in packet.layers
        return len(field_values(packet, node.field)) > 0
    values = field_values(packet, node.field)
    if not values:
        return False
    if node.operator == "!=":
        return all(value != node.value for value in values)
    return any(compare(value, node.operator, node.value) for value in values)


def filter_block(expression, packets, summaries):
    lines = ["", f"filter {expression}"]
    try:
        tree = FilterParser(tokenize(expression)).parse()
    except FilterError as error:
        lines.append(f"error: {error}")
        return lines
    matched = [packet for packet in packets if evaluate(tree, packet)]
    lines.extend(summaries[packet.number - 1] for packet in matched)
    lines.append(f"matched {len(matched)} of {len(packets)}")
    return lines


def detail_lines(packets, number):
    if not 1 <= number <= len(packets):
        return [f"packet {number} not found"]
    packet = packets[number - 1]
    lines = [f"packet {number}"]
    for layer in ["frame"] + packet.layers:
        lines.append(layer)
        prefix = layer + "."
        for name, field_type in FIELDS:
            if not name.startswith(prefix):
                continue
            for value in packet.values(name):
                if field_type == "presence":
                    lines.append("  " + name)
                else:
                    lines.append(f"  {name} = {notation(field_type, value)}")
        if layer == "data":
            lines.extend("  " + line for line in hex_dump_lines(packet.remaining))
    return lines


def is_answer(query, response):
    return (
        query.value("dns.id") == response.value("dns.id")
        and query.value("ip.src") == response.value("ip.dst")
        and query.value("udp.srcport") == response.value("udp.dstport")
        and query.value("ip.dst") == response.value("ip.src")
        and query.value("udp.dstport") == response.value("udp.srcport")
    )


class DnsTransactions:
    def __init__(self, packets):
        self.queries = []
        self.responses = []
        self.response_times = []
        pending = []
        for packet in packets:
            if not packet.exists("dns.id"):
                continue
            if packet.value("dns.flags.response") == 0:
                self.queries.append(packet)
                pending.append(packet)
                continue
            self.responses.append(packet)
            for index, query in enumerate(pending):
                if is_answer(query, packet):
                    del pending[index]
                    self.response_times.append(packet.time - query.time)
                    break
        self.unanswered = len(pending)


def layer_statistics(packets):
    lines = ["hierarchy"]
    for name, indent in HIERARCHY:
        members = [packet for packet in packets if name in packet.layers]
        total = sum(packet.length for packet in members)
        lines.append(f"{' ' * indent}{name} {len(members)} {total}")
    lines.append("checksums")
    for layer, _ in CHECKSUM_LAYERS:
        statuses = [packet.value(layer + ".checksum.status") for packet in packets]
        line = f"{layer} good {statuses.count('good')} bad {statuses.count('bad')}"
        if layer == "udp":
            line += f" none {statuses.count('none')}"
        lines.append(line)
    lines.append("malformed")
    lines.append(f"dump {sum(packet.error is not None for packet in packets)}")
    for name in MALFORMED_LAYERS:
        count = sum(
            packet.error is None and packet.exists("frame.malformed") and packet.layers[-1] == name
            for packet in packets
        )
        lines.append(f"{name} {count}")
    lines.append("tcp analysis")
    for mark in MARKS:
        count = sum(packet.exists("tcp.analysis." + mark) for packet in packets)
        lines.append(f"{mark} {count}")
    return lines


def dns_statistics(transactions):
    lines = [
        "dns",
        f"queries {len(transactions.queries)}",
        f"responses {len(transactions.responses)}",
        f"transactions {len(transactions.response_times)}",
        f"unanswered {transactions.unanswered}",
    ]
    times = transactions.response_times
    if times:
        lines.append(f"response_time min {seconds(min(times))} max {seconds(max(times))}")
    else:
        lines.append("response_time -")
    rcodes = [response.value("dns.flags.rcode") for response in transactions.responses]
    for rcode in range(RCODE_COUNT):
        if rcodes.count(rcode) > 0:
            lines.append(f"rcode {rcode_name(rcode)} {rcodes.count(rcode)}")
    lines.append("names")
    name_counts = {}
    for query in transactions.queries:
        for name in query.values("dns.qry.name"):
            name_counts[name] = name_counts.get(name, 0) + 1
    for name, count in sorted(name_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"{name} {count}")
    return lines


def protocol_stats_lines(packets, transactions):
    duration = packets[-1].time - packets[0].time
    lines = [
        f"packets {len(packets)}",
        f"bytes {sum(packet.length for packet in packets)}",
        f"duration {seconds(duration)}",
    ]
    lines.extend(layer_statistics(packets))
    lines.extend(dns_statistics(transactions))
    return lines


def conversation_lines(conversations, base_time):
    lines = [CONVERSATION_HEADER]
    for conversation in conversations:
        columns = (
            conversation.kind,
            endpoint_text(conversation.endpoint_a),
            endpoint_text(conversation.endpoint_b),
            conversation.packets(),
            conversation.bytes(),
            conversation.packets_a_to_b,
            conversation.bytes_a_to_b,
            conversation.packets_b_to_a,
            conversation.bytes_b_to_a,
            seconds(conversation.first_time - base_time),
            seconds(conversation.last_time - conversation.first_time),
        )
        lines.append(",".join(str(column) for column in columns))
    return lines


def endpoint_lines(endpoints):
    lines = [ENDPOINT_HEADER]
    for endpoint in endpoints:
        columns = (
            ipv4_notation(endpoint.address),
            endpoint.packets(),
            endpoint.bytes(),
            endpoint.tx_packets,
            endpoint.tx_bytes,
            endpoint.rx_packets,
            endpoint.rx_bytes,
        )
        lines.append(",".join(str(column) for column in columns))
    return lines


def side_line(side):
    counts = " ".join(f"{mark} {side.marks[mark]}" for mark in MARKS)
    return f"{side.name} packets {side.packets} payload {side.payload} {counts}"


def stream_lines(stream, packets):
    base_time = packets[0].time
    client = stream.client_side
    server = stream.server_side
    rtt = "-"
    if stream.syn is not None and stream.handshake_ack is not None:
        rtt = seconds(packets[stream.handshake_ack - 1].time - packets[stream.syn - 1].time)
    lines = [
        f"stream {stream.number} {endpoint_text(stream.client)} -> {endpoint_text(stream.server)}",
        f"packets {stream.packets} bytes {stream.bytes} start {seconds(stream.start - base_time)}"
        f" duration {seconds(stream.end - stream.start)}",
        "states " + ", ".join(f"{state} {number}" for state, number in stream.history),
        f"handshake syn {optional(stream.syn)} syn_ack {optional(stream.syn_ack)}"
        f" ack {optional(stream.handshake_ack)} rtt {rtt}",
        f"options client mss {optional(client.mss)} wscale {optional(client.wscale)}"
        f" server mss {optional(server.mss)} wscale {optional(server.wscale)}",
        side_line(client),
        side_line(server),
    ]
    for number, side_name, mark, start, size in stream.events:
        lines.append(f"event {number} {side_name} {mark} seq {start} len {size}")
    return lines


def joined_blocks(blocks):
    lines = []
    for index, block in enumerate(blocks):
        if index > 0:
            lines.append("")
        lines.extend(block)
    return lines


def read_requests(path):
    filters = []
    details = []
    for line in read_lines(path):
        if line.startswith("FILTER "):
            filters.append(line[len("FILTER "):])
        elif line.startswith("DETAIL "):
            details.append(int(line[len("DETAIL "):]))
    return filters, details


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def main():
    packets = read_capture(os.path.join(INPUT_DIR, "capture.txt"))
    filters, detail_numbers = read_requests(os.path.join(INPUT_DIR, "filters.txt"))
    base_time = packets[0].time
    for packet in packets:
        dissect(packet, base_time)
    tracker = StreamTracker()
    for packet in packets:
        if packet.exists("tcp.srcport"):
            tracker.track(packet)
    summaries = [summary_line(packet, tracker.duplicate_acks) for packet in packets]
    summary = list(summaries)
    for expression in filters:
        summary.extend(filter_block(expression, packets, summaries))
    details = joined_blocks(detail_lines(packets, number) for number in detail_numbers)
    streams = joined_blocks(stream_lines(stream, packets) for stream in tracker.streams)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("summary.txt", summary)
    write_lines("details.txt", details)
    write_lines("conversations.csv", conversation_lines(build_conversations(packets), base_time))
    write_lines("endpoints.csv", endpoint_lines(build_endpoints(packets)))
    write_lines("protocol_stats.txt", protocol_stats_lines(packets, DnsTransactions(packets)))
    write_lines("tcp_streams.txt", streams)


if __name__ == "__main__":
    main()
