SEQUENCE_MODULUS = 2 ** 32
OUT_OF_ORDER_LIMIT = 3000
MARKS = ("retransmission", "out_of_order", "lost_segment", "duplicate_ack")
CONVERSATION_KINDS = ("ipv4", "tcp", "udp")
SYN_SENT = "SYN_SENT"
SYN_RECEIVED = "SYN_RECEIVED"
ESTABLISHED = "ESTABLISHED"
FIN_WAIT = "FIN_WAIT"
CLOSING = "CLOSING"
CLOSED = "CLOSED"
RESET = "RESET"


class Segment:
    def __init__(self, packet):
        self.packet = packet
        self.number = packet.number
        self.time = packet.time
        self.source = (packet.value("ip.src"), packet.value("tcp.srcport"))
        self.destination = (packet.value("ip.dst"), packet.value("tcp.dstport"))
        self.seq = packet.value("tcp.seq_raw")
        self.ack = packet.value("tcp.ack_raw")
        self.fin = packet.value("tcp.flags.fin")
        self.syn = packet.value("tcp.flags.syn")
        self.rst = packet.value("tcp.flags.rst")
        self.has_ack = packet.value("tcp.flags.ack")
        self.window = packet.value("tcp.window")
        self.length = packet.value("tcp.len")

    def syn_only(self):
        return self.syn == 1 and self.has_ack == 0

    def syn_ack(self):
        return self.syn == 1 and self.has_ack == 1


class PreviousAck:
    def __init__(self, ack, window, number):
        self.ack = ack
        self.window = window
        self.number = number
        self.count = 0


class Side:
    def __init__(self, name):
        self.name = name
        self.isn = None
        self.mss = None
        self.wscale = None
        self.base = None
        self.expected = None
        self.advanced_at = None
        self.intervals = set()
        self.previous_ack = None
        self.packets = 0
        self.payload = 0
        self.marks = dict.fromkeys(MARKS, 0)


class Stream:
    def __init__(self, number, client, server, state, segment):
        self.number = number
        self.client = client
        self.server = server
        self.state = state
        self.history = [(state, segment.number)]
        self.start = segment.time
        self.end = segment.time
        self.packets = 0
        self.bytes = 0
        self.syn = None
        self.syn_ack = None
        self.handshake_ack = None
        self.events = []
        self.closer = None
        self.final_ack = None
        self.client_side = Side("client")
        self.server_side = Side("server")

    def change_state(self, state, number):
        self.state = state
        self.history.append((state, number))

    def record_syn(self, side, segment):
        side.isn = segment.seq
        side.mss = segment.packet.value("tcp.options.mss")
        side.wscale = segment.packet.value("tcp.options.wscale")
        if side is self.client_side:
            self.syn = segment.number
        else:
            self.syn_ack = segment.number


def endpoint_pair(first, second):
    return (first, second) if first <= second else (second, first)


def sequence_mark(side, start, size, time):
    if side.expected is None or start == side.expected:
        return None
    if start > side.expected:
        return "lost_segment"
    if (start, size) in side.intervals:
        return "retransmission"
    if time - side.advanced_at < OUT_OF_ORDER_LIMIT:
        return "out_of_order"
    return "retransmission"


class StreamTracker:
    def __init__(self):
        self.streams = []
        self.latest = {}
        self.duplicate_acks = {}

    def open_stream(self, segment):
        number = len(self.streams)
        if segment.syn_ack():
            stream = Stream(number, segment.destination, segment.source, SYN_RECEIVED, segment)
            stream.record_syn(stream.server_side, segment)
        elif segment.syn_only():
            stream = Stream(number, segment.source, segment.destination, SYN_SENT, segment)
            stream.record_syn(stream.client_side, segment)
        else:
            stream = Stream(number, segment.source, segment.destination, ESTABLISHED, segment)
        self.streams.append(stream)
        return stream

    def find_stream(self, segment):
        key = endpoint_pair(segment.source, segment.destination)
        stream = self.latest.get(key)
        if stream is None or (stream.state in (CLOSED, RESET) and segment.syn_only()):
            stream = self.open_stream(segment)
            self.latest[key] = stream
        return stream

    def track(self, packet):
        segment = Segment(packet)
        stream = self.find_stream(segment)
        packet.set("tcp.stream", stream.number)
        if segment.source == stream.client:
            side, other = stream.client_side, stream.server_side
        else:
            side, other = stream.server_side, stream.client_side
        if side.base is None:
            side.base = segment.seq
        if segment.has_ack and other.base is None:
            other.base = segment.ack
        relative_seq = (segment.seq - side.base) % SEQUENCE_MODULUS
        packet.set("tcp.seq", relative_seq)
        if segment.has_ack:
            packet.set("tcp.ack", (segment.ack - other.base) % SEQUENCE_MODULUS)
        self.analyze(stream, side, segment, relative_seq)
        packet.set("tcp.window.calc", self.calculated_window(stream, side, segment))
        self.transition(stream, side, segment)
        side.packets += 1
        side.payload += segment.length
        stream.packets += 1
        stream.bytes += packet.length
        stream.end = segment.time

    def analyze(self, stream, side, segment, start):
        size = segment.length + segment.syn + segment.fin
        mark = None
        if size >= 1:
            mark = sequence_mark(side, start, size, segment.time)
            side.intervals.add((start, size))
            if side.expected is None or start + size > side.expected:
                side.expected = start + size
                side.advanced_at = segment.time
        elif segment.has_ack and not segment.rst:
            previous = side.previous_ack
            if previous is not None and segment.ack == previous.ack and segment.window == previous.window:
                mark = "duplicate_ack"
                previous.count += 1
                self.duplicate_acks[segment.number] = (previous.number, previous.count)
        if segment.has_ack and mark != "duplicate_ack":
            side.previous_ack = PreviousAck(segment.ack, segment.window, segment.number)
        if mark is not None:
            segment.packet.set("tcp.analysis." + mark, True)
            side.marks[mark] += 1
            stream.events.append((segment.number, side.name, mark, start, size))

    def calculated_window(self, stream, side, segment):
        scaled = stream.client_side.wscale is not None and stream.server_side.wscale is not None
        if scaled and not segment.syn:
            return segment.window * 2 ** side.wscale
        return segment.window

    def transition(self, stream, side, segment):
        number = segment.number
        state = stream.state
        if segment.rst:
            if state not in (CLOSED, RESET):
                stream.change_state(RESET, number)
        elif (
            state == SYN_SENT
            and segment.syn_ack()
            and side is stream.server_side
            and segment.ack == (stream.client_side.isn + 1) % SEQUENCE_MODULUS
        ):
            stream.change_state(SYN_RECEIVED, number)
            stream.record_syn(stream.server_side, segment)
        elif (
            state == SYN_RECEIVED
            and side is stream.client_side
            and segment.has_ack
            and not segment.syn
            and segment.ack == (stream.server_side.isn + 1) % SEQUENCE_MODULUS
        ):
            stream.change_state(ESTABLISHED, number)
            stream.handshake_ack = number
        elif state == ESTABLISHED and segment.fin:
            stream.change_state(FIN_WAIT, number)
            stream.closer = side
        elif state == FIN_WAIT and segment.fin and side is not stream.closer:
            stream.change_state(CLOSING, number)
            stream.final_ack = (segment.seq + segment.length + 1) % SEQUENCE_MODULUS
        elif state == CLOSING and side is stream.closer and segment.has_ack and segment.ack == stream.final_ack:
            stream.change_state(CLOSED, number)


class Conversation:
    def __init__(self, kind, endpoint_a, endpoint_b, packet):
        self.kind = kind
        self.endpoint_a = endpoint_a
        self.endpoint_b = endpoint_b
        self.first_number = packet.number
        self.first_time = packet.time
        self.last_time = packet.time
        self.packets_a_to_b = 0
        self.bytes_a_to_b = 0
        self.packets_b_to_a = 0
        self.bytes_b_to_a = 0

    def count(self, source, packet):
        if source == self.endpoint_a:
            self.packets_a_to_b += 1
            self.bytes_a_to_b += packet.length
        else:
            self.packets_b_to_a += 1
            self.bytes_b_to_a += packet.length
        self.last_time = packet.time

    def packets(self):
        return self.packets_a_to_b + self.packets_b_to_a

    def bytes(self):
        return self.bytes_a_to_b + self.bytes_b_to_a


def conversation_views(packet):
    source_ip = packet.value("ip.src")
    destination_ip = packet.value("ip.dst")
    views = [(
        "ipv4", endpoint_pair(source_ip, destination_ip),
        (source_ip, None), (destination_ip, None),
    )]
    if packet.exists("tcp.stream"):
        source = (source_ip, packet.value("tcp.srcport"))
        destination = (destination_ip, packet.value("tcp.dstport"))
        views.append(("tcp", packet.value("tcp.stream"), source, destination))
    if packet.exists("udp.srcport"):
        source = (source_ip, packet.value("udp.srcport"))
        destination = (destination_ip, packet.value("udp.dstport"))
        views.append(("udp", endpoint_pair(source, destination), source, destination))
    return views


def build_conversations(packets):
    conversations = []
    table = {}
    for packet in packets:
        if not packet.exists("ip.src"):
            continue
        for kind, key, source, destination in conversation_views(packet):
            conversation = table.get((kind, key))
            if conversation is None:
                conversation = Conversation(kind, source, destination, packet)
                table[(kind, key)] = conversation
                conversations.append(conversation)
            conversation.count(source, packet)
    conversations.sort(key=lambda conversation: (
        -conversation.bytes(),
        -conversation.packets(),
        CONVERSATION_KINDS.index(conversation.kind),
        conversation.first_number,
    ))
    return conversations


class Endpoint:
    def __init__(self, address):
        self.address = address
        self.tx_packets = 0
        self.tx_bytes = 0
        self.rx_packets = 0
        self.rx_bytes = 0

    def packets(self):
        return self.tx_packets + self.rx_packets

    def bytes(self):
        return self.tx_bytes + self.rx_bytes


def build_endpoints(packets):
    table = {}
    for packet in packets:
        if not packet.exists("ip.src"):
            continue
        source = packet.value("ip.src")
        destination = packet.value("ip.dst")
        sender = table.setdefault(source, Endpoint(source))
        sender.tx_packets += 1
        sender.tx_bytes += packet.length
        receiver = table.setdefault(destination, Endpoint(destination))
        receiver.rx_packets += 1
        receiver.rx_bytes += packet.length
    return sorted(
        table.values(),
        key=lambda endpoint: (-endpoint.bytes(), -endpoint.packets(), endpoint.address),
    )
