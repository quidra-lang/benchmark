import sys


DEFAULT_TIMEOUTS = {"TCP": 300, "UDP": 60, "ICMP": 30}
DROP_REASONS = (
    "down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted",
)
MARTIAN_NETWORKS = ((0x00000000, 8), (0x7F000000, 8), (0xE0000000, 3))
DIRECTIONS = ("in", "out")
TCP_FLAGS = "SAFR"
DIGITS = "0123456789"
ALL_BITS = 0xFFFFFFFF
PAT_FIRST_PORT = 20000
MAX_PORT = 65535
MAX_SECONDS = 86400


class CommandError(Exception):
    pass


def parse_decimal(text, max_digits):
    if not 1 <= len(text) <= max_digits:
        return None
    if any(character not in DIGITS for character in text):
        return None
    if len(text) > 1 and text[0] == "0":
        return None
    return int(text)


def parse_address(text):
    fields = text.split(".")
    if len(fields) != 4:
        return None
    value = 0
    for field in fields:
        number = parse_decimal(field, 3)
        if number is None or number > 255:
            return None
        value = value * 256 + number
    return value


def parse_prefix(text):
    if text.count("/") != 1:
        return None
    address_part, length_part = text.split("/")
    address = parse_address(address_part)
    length = parse_decimal(length_part, 2)
    if address is None or length is None or length > 32:
        return None
    return address, length


def network_mask(length):
    return (ALL_BITS << (32 - length)) & ALL_BITS


def network_of(address, length):
    return address & network_mask(length)


def contains(network, length, address):
    return network_of(address, length) == network_of(network, length)


def address_text(value):
    return f"{value >> 24}.{(value >> 16) & 255}.{(value >> 8) & 255}.{value & 255}"


def prefix_text(network, length):
    return f"{address_text(network)}/{length}"


def endpoint(address, port):
    return f"{address_text(address)}:{port}"


def flow_text(flow):
    _, source, source_port, destination, destination_port = flow
    return f"{endpoint(source, source_port)} > {endpoint(destination, destination_port)}"


def require_address(text):
    address = parse_address(text)
    if address is None:
        raise CommandError(f"bad address {text}")
    return address


def require_prefix(text):
    prefix = parse_prefix(text)
    if prefix is None:
        raise CommandError(f"bad prefix {text}")
    address, length = prefix
    if network_of(address, length) != address:
        raise CommandError(f"host bits set in {text}")
    return prefix


def require_acl_prefix(text):
    if text == "ANY":
        return 0, 0
    return require_prefix(text)


def require_number(text, minimum, maximum, message):
    value = int(text)
    if not minimum <= value <= maximum:
        raise CommandError(message)
    return value


def valid_tcp_flags(flags):
    return all(flag in TCP_FLAGS and flags.count(flag) == 1 for flag in flags)


class PortRange:
    def __init__(self, low, high, label):
        self.low = low
        self.high = high
        self.label = label

    def contains(self, port):
        return self.low <= port <= self.high


def require_port_range(text):
    if text == "ANY":
        return PortRange(0, MAX_PORT, "any")
    bounds = [int(part) for part in text.split("-")]
    low, high = bounds[0], bounds[-1]
    if any(bound > MAX_PORT for bound in bounds) or low > high:
        raise CommandError(f"bad port range {text}")
    label = str(low) if low == high else f"{low}-{high}"
    return PortRange(low, high, label)


class AccessRule:
    def __init__(self, sequence, action, protocol, source, source_ports,
                 destination, destination_ports, established):
        self.sequence = sequence
        self.action = action
        self.protocol = protocol
        self.source = source
        self.source_ports = source_ports
        self.destination = destination
        self.destination_ports = destination_ports
        self.established = established
        self.hits = 0

    def matches(self, flow, established):
        protocol, source, source_port, destination, destination_port = flow
        if self.protocol != "ANY" and self.protocol != protocol:
            return False
        if not contains(*self.source, source) or not contains(*self.destination, destination):
            return False
        if self.protocol in ("TCP", "UDP"):
            if not self.source_ports.contains(source_port):
                return False
            if not self.destination_ports.contains(destination_port):
                return False
        return established or not self.established

    def description(self, interface_name, direction):
        parts = [
            "acl", interface_name, direction, self.sequence, self.action, self.protocol,
            acl_prefix_text(self.source), self.source_ports.label,
            acl_prefix_text(self.destination), self.destination_ports.label,
        ]
        if self.established:
            parts.append("established")
        parts.append(f"hits={self.hits}")
        return " ".join(str(part) for part in parts)


def acl_prefix_text(prefix):
    network, length = prefix
    return "any" if length == 0 else prefix_text(network, length)


class AccessList:
    def __init__(self, interface_name, direction):
        self.interface_name = interface_name
        self.direction = direction
        self.rules = []
        self.default_hits = 0

    def find(self, sequence):
        for rule in self.rules:
            if rule.sequence == sequence:
                return rule
        return None

    def add(self, rule):
        self.rules.append(rule)
        self.rules.sort(key=lambda item: item.sequence)

    def evaluate(self, flow, established):
        if not self.rules:
            return None
        protocol = flow[0]
        label = f"acl {self.interface_name} {self.direction}"
        for rule in self.rules:
            if not rule.matches(flow, established):
                continue
            rule.hits += 1
            if rule.action == "PERMIT":
                return None
            if rule.action == "DENY":
                return f"DROP {label} {rule.sequence}"
            reason = "tcp-reset" if protocol == "TCP" else "icmp-prohibited"
            return f"REJECT {label} {rule.sequence} {reason}"
        self.default_hits += 1
        return f"DROP {label} default"

    def clear_counters(self):
        self.default_hits = 0
        for rule in self.rules:
            rule.hits = 0


class Interface:
    def __init__(self, name, address, length):
        self.name = name
        self.address = address
        self.length = length
        self.up = True
        self.outside = False
        self.pat_size = None
        self.pat_mappings = []
        self.rpf = "off"
        self.rx = 0
        self.tx = 0
        self.drop = 0
        self.acls = {direction: AccessList(name, direction) for direction in DIRECTIONS}

    def contains(self, address):
        return contains(self.address, self.length, address)

    def description(self):
        parts = [
            self.name, prefix_text(self.address, self.length),
            "up" if self.up else "down",
            "outside" if self.outside else "inside",
            f"rpf={self.rpf}",
        ]
        if self.pat_size is not None:
            parts.append(f"pat={len(self.pat_mappings)}/{self.pat_size}")
        return " ".join(parts)


class Route:
    def __init__(self, kind, network, length, interface, next_hop, metric):
        self.kind = kind
        self.network = network
        self.length = length
        self.interface = interface
        self.next_hop = next_hop
        self.metric = metric
        self.hits = 0

    def active(self):
        return self.interface.up

    def is_static_to(self, network, length):
        return self.kind == "S" and self.network == network and self.length == length

    def notation(self):
        parts = [self.kind, prefix_text(self.network, self.length)]
        if self.next_hop is not None:
            parts.extend(("via", address_text(self.next_hop)))
        parts.extend(("dev", self.interface.name, "metric", str(self.metric)))
        return " ".join(parts)


class StaticNat:
    def __init__(self, inside, outside):
        self.inside = inside
        self.outside = outside


class PortForward:
    def __init__(self, interface, protocol, outside_port, inside_address, inside_port):
        self.interface = interface
        self.protocol = protocol
        self.outside_port = outside_port
        self.inside_address = inside_address
        self.inside_port = inside_port


class PatMapping:
    def __init__(self, protocol, inside_address, inside_port, outside_port, last_used):
        self.protocol = protocol
        self.inside_address = inside_address
        self.inside_port = inside_port
        self.outside_port = outside_port
        self.last_used = last_used


class Connection:
    def __init__(self, number, orig, reply, inbound, outbound):
        self.number = number
        self.protocol = orig[0]
        self.orig = orig
        self.reply = reply
        self.inbound = inbound
        self.outbound = outbound
        self.state = "SYN_SENT" if self.protocol == "TCP" else "UNREPLIED"
        self.orig_packets = 0
        self.reply_packets = 0
        self.last_used = 0
        self.orig_fin = False
        self.reply_fin = False

    def record(self, direction, flags, now):
        if direction == "reply":
            self.reply_packets += 1
        else:
            self.orig_packets += 1
        self.last_used = now
        self.update_state(direction, flags)

    def update_state(self, direction, flags):
        if self.protocol != "TCP":
            if direction == "reply":
                self.state = "REPLIED"
            return
        if "R" in flags:
            self.state = "CLOSED"
            return
        if self.state == "SYN_SENT" and direction == "reply" and "S" in flags and "A" in flags:
            self.state = "ESTABLISHED"
        if "F" in flags and self.state in ("ESTABLISHED", "FIN_WAIT"):
            if direction == "reply":
                self.reply_fin = True
            else:
                self.orig_fin = True
            self.state = "CLOSED" if self.orig_fin and self.reply_fin else "FIN_WAIT"

    def timeout(self, timeouts):
        if self.protocol != "TCP":
            return timeouts[self.protocol]
        if self.state == "ESTABLISHED":
            return timeouts["TCP"]
        if self.state == "CLOSED":
            return 10
        return 60

    def description(self, now):
        return " ".join((
            "conn", str(self.number), self.protocol, flow_text(self.orig),
            "reply", flow_text(self.reply),
            f"in={self.inbound.name}", f"out={self.outbound.name}", f"state={self.state}",
            f"pkts={self.orig_packets}/{self.reply_packets}", f"idle={now - self.last_used}",
        ))


class Packet:
    def __init__(self, interface, protocol, flags, source, source_port,
                 destination, destination_port, ttl):
        self.interface = interface
        self.protocol = protocol
        self.flags = flags
        self.source = source
        self.source_port = source_port
        self.destination = destination
        self.destination_port = destination_port
        self.ttl = ttl

    def flow(self):
        return (
            self.protocol, self.source, self.source_port,
            self.destination, self.destination_port,
        )

    def pure_syn(self):
        return self.protocol == "TCP" and self.flags == "S"


class Router:
    def __init__(self):
        self.interfaces = {}
        self.routes = []
        self.statics = []
        self.forwards = []
        self.connections = []
        self.timeouts = dict(DEFAULT_TIMEOUTS)
        self.clock = 0
        self.packet_count = 0
        self.connection_count = 0
        self.counts = self.empty_counts()
        self.errors = 0
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def empty_counts(self):
        return dict.fromkeys(("forwarded", "local") + DROP_REASONS, 0)

    def interface(self, name):
        if name not in self.interfaces:
            raise CommandError(f"no interface {name}")
        return self.interfaces[name]

    def sorted_interfaces(self):
        return sorted(self.interfaces.values(), key=lambda interface: interface.name)

    def interface_with_address(self, address):
        for interface in self.interfaces.values():
            if interface.address == address:
                return interface
        return None

    def interface_containing(self, address):
        for interface in self.interfaces.values():
            if interface.contains(address):
                return interface
        return None

    def select_route(self, address):
        best = None
        for route in self.routes:
            if not route.active() or not contains(route.network, route.length, address):
                continue
            if best is None or route.length > best.length:
                best = route
            elif route.length == best.length and route.metric < best.metric:
                best = route
        return best

    def add_interface(self, arguments):
        name, cidr = arguments
        if name in self.interfaces:
            raise CommandError(f"duplicate interface {name}")
        prefix = parse_prefix(cidr)
        if prefix is None or not 8 <= prefix[1] <= 30:
            raise CommandError(f"bad prefix {cidr}")
        address, length = prefix
        host_mask = ALL_BITS ^ network_mask(length)
        host = address & host_mask
        if host == 0 or host == host_mask:
            raise CommandError(f"bad host address {cidr}")
        for other in self.interfaces.values():
            if contains(other.address, min(length, other.length), address):
                raise CommandError(f"subnet overlaps {other.name}")
        interface = Interface(name, address, length)
        self.interfaces[name] = interface
        network = network_of(address, length)
        self.routes.append(Route("C", network, length, interface, None, 0))
        self.emit("ok", "iface", name, cidr, "network", prefix_text(network, length))

    def set_status(self, arguments, up):
        name = arguments[0]
        interface = self.interface(name)
        word = "up" if up else "down"
        if interface.up == up:
            raise CommandError(f"interface {name} already {word}")
        interface.up = up
        self.emit("ok", word, name)

    def bring_up(self, arguments):
        self.set_status(arguments, True)

    def bring_down(self, arguments):
        self.set_status(arguments, False)

    def add_route(self, arguments):
        prefix_word, mode, target, metric_word = arguments
        network, length = require_prefix(prefix_word)
        next_hop = None
        interface = None
        if mode == "VIA":
            next_hop = require_address(target)
        else:
            interface = self.interface(target)
        metric = require_number(metric_word, 1, 255, f"bad metric {metric_word}")
        if mode == "VIA":
            if self.interface_with_address(next_hop) is not None:
                raise CommandError(f"nexthop {target} is local")
            interface = self.interface_containing(next_hop)
            if interface is None:
                raise CommandError(f"nexthop {target} unreachable")
        for route in self.routes:
            if (route.is_static_to(network, length) and route.interface is interface
                    and route.next_hop == next_hop):
                raise CommandError(f"duplicate route {prefix_word}")
        route = Route("S", network, length, interface, next_hop, metric)
        self.routes.append(route)
        self.emit("ok", "route", route.notation())

    def remove_route(self, arguments):
        prefix_word = arguments[0]
        network, length = require_prefix(prefix_word)
        kept = [route for route in self.routes if not route.is_static_to(network, length)]
        removed = len(self.routes) - len(kept)
        if removed == 0:
            raise CommandError(f"no static route {prefix_word}")
        self.routes = kept
        self.emit("ok", "noroute", prefix_word, f"removed={removed}")

    def lookup(self, arguments):
        address_word = arguments[0]
        route = self.select_route(require_address(address_word))
        self.emit("lookup", address_word, "none" if route is None else route.notation())

    def add_rule(self, arguments):
        (name, direction_word, sequence_word, action, protocol, source_word,
         source_ports_word, destination_word, destination_ports_word) = arguments[:9]
        interface = self.interface(name)
        sequence = require_number(sequence_word, 1, 9999, f"bad sequence {sequence_word}")
        source = require_acl_prefix(source_word)
        source_ports = require_port_range(source_ports_word)
        destination = require_acl_prefix(destination_word)
        destination_ports = require_port_range(destination_ports_word)
        if protocol in ("ICMP", "ANY") and (
            source_ports_word != "ANY" or destination_ports_word != "ANY"
        ):
            raise CommandError(f"ports not allowed for {protocol}")
        direction = direction_word.lower()
        access_list = interface.acls[direction]
        if access_list.find(sequence) is not None:
            raise CommandError(f"duplicate sequence {sequence_word}")
        established = arguments[-1] == "ESTABLISHED"
        access_list.add(AccessRule(
            sequence, action, protocol, source, source_ports,
            destination, destination_ports, established,
        ))
        self.emit("ok", "acl", name, direction, sequence_word)

    def remove_rule(self, arguments):
        name, direction_word, sequence_word = arguments
        interface = self.interface(name)
        direction = direction_word.lower()
        access_list = interface.acls[direction]
        rule = access_list.find(int(sequence_word))
        if rule is None:
            raise CommandError(f"no rule {sequence_word} on {name} {direction}")
        access_list.rules.remove(rule)
        self.emit("ok", "noacl", name, direction, sequence_word, f"hits={rule.hits}")

    def nat(self, arguments):
        handlers = {
            "STATIC": self.add_static,
            "OUTSIDE": self.set_outside,
            "PAT": self.add_pat,
            "FORWARD": self.add_forward,
        }
        handlers[arguments[0]](arguments[1:])

    def add_static(self, arguments):
        inside_word, outside_word = arguments
        inside = require_address(inside_word)
        outside = require_address(outside_word)
        for address, word in ((inside, inside_word), (outside, outside_word)):
            if self.interface_with_address(address) is not None:
                raise CommandError(f"address {word} is local")
        if any(mapping.inside == inside for mapping in self.statics):
            raise CommandError(f"duplicate static {inside_word}")
        if any(mapping.outside == outside for mapping in self.statics):
            raise CommandError(f"duplicate static {outside_word}")
        self.statics.append(StaticNat(inside, outside))
        self.emit("ok", "nat", "static", inside_word, outside_word)

    def set_outside(self, arguments):
        name = arguments[0]
        interface = self.interface(name)
        if interface.outside:
            raise CommandError(f"interface {name} already outside")
        interface.outside = True
        self.emit("ok", "nat", "outside", name)

    def add_pat(self, arguments):
        name, count_word = arguments
        interface = self.interface(name)
        size = require_number(count_word, 1, 1000, f"bad pool size {count_word}")
        if interface.pat_size is not None:
            raise CommandError(f"pat already on {name}")
        interface.pat_size = size
        interface.outside = True
        last_port = PAT_FIRST_PORT + size - 1
        self.emit(
            "ok", "nat", "pat", name, address_text(interface.address),
            f"{PAT_FIRST_PORT}-{last_port}",
        )

    def add_forward(self, arguments):
        name, protocol, port_word, inside_word, inside_port_word = arguments
        interface = self.interface(name)
        port = require_number(port_word, 1, MAX_PORT, f"bad port {port_word}")
        inside = require_address(inside_word)
        inside_port = require_number(
            inside_port_word, 1, MAX_PORT, f"bad port {inside_port_word}"
        )
        if not interface.outside:
            raise CommandError(f"interface {name} not outside")
        if self.interface_with_address(inside) is not None:
            raise CommandError(f"address {inside_word} is local")
        for forward in self.forwards:
            if (forward.interface is interface and forward.protocol == protocol
                    and forward.outside_port == port):
                raise CommandError(f"duplicate forward {name} {protocol} {port_word}")
        self.forwards.append(PortForward(interface, protocol, port, inside, inside_port))
        self.emit(
            "ok", "nat", "forward", name, protocol, port_word,
            f"{inside_word}:{inside_port_word}",
        )

    def set_rpf(self, arguments):
        name, mode = arguments
        interface = self.interface(name)
        interface.rpf = mode.lower()
        self.emit("ok", "rpf", name, interface.rpf)

    def set_timeout(self, arguments):
        protocol, seconds_word = arguments
        seconds = require_number(seconds_word, 1, MAX_SECONDS, f"bad timeout {seconds_word}")
        self.timeouts[protocol] = seconds
        self.emit("ok", "timeout", protocol, seconds_word)

    def tick(self, arguments):
        seconds_word = arguments[0]
        seconds = require_number(seconds_word, 1, MAX_SECONDS, f"bad tick {seconds_word}")
        self.clock += seconds
        kept = [
            connection for connection in self.connections
            if self.clock - connection.last_used < connection.timeout(self.timeouts)
        ]
        expired_connections = len(self.connections) - len(kept)
        self.connections = kept
        expired_mappings = 0
        for interface in self.interfaces.values():
            kept_mappings = [
                mapping for mapping in interface.pat_mappings
                if self.clock - mapping.last_used < self.timeouts[mapping.protocol]
            ]
            expired_mappings += len(interface.pat_mappings) - len(kept_mappings)
            interface.pat_mappings = kept_mappings
        self.emit(
            "ok", "tick", f"time={self.clock}", "expired",
            f"conns={expired_connections}", f"nat={expired_mappings}",
        )

    def packet(self, arguments):
        (name, protocol, flags, source_word, source_port_word,
         destination_word, destination_port_word, ttl_word) = arguments
        interface = self.interface(name)
        if protocol != "TCP" and flags != "-":
            raise CommandError(f"flags not allowed for {protocol}")
        if protocol == "TCP" and flags != "-" and not valid_tcp_flags(flags):
            raise CommandError(f"bad flags {flags}")
        source = require_address(source_word)
        source_port = require_number(
            source_port_word, 0, MAX_PORT, f"bad port {source_port_word}"
        )
        destination = require_address(destination_word)
        destination_port = require_number(
            destination_port_word, 0, MAX_PORT, f"bad port {destination_port_word}"
        )
        ttl = require_number(ttl_word, 1, 255, f"bad ttl {ttl_word}")
        self.packet_count += 1
        interface.rx += 1
        packet = Packet(
            interface, protocol, "" if flags == "-" else flags,
            source, source_port, destination, destination_port, ttl,
        )
        reason, verdict = self.process(packet)
        self.counts[reason] += 1
        if reason in DROP_REASONS:
            interface.drop += 1
        self.emit(
            f"#{self.packet_count}", protocol, flags,
            f"{source_word}:{source_port_word}", ">",
            f"{destination_word}:{destination_port_word}", verdict,
        )

    def martian(self, source, destination):
        for network, length in MARTIAN_NETWORKS:
            if contains(network, length, source) or contains(network, length, destination):
                return True
        return self.interface_with_address(source) is not None

    def find_connection(self, packet):
        flow = packet.flow()
        for connection in self.connections:
            if connection.orig == flow:
                direction = "orig"
            elif connection.reply == flow:
                direction = "reply"
            else:
                continue
            if connection.state == "CLOSED" and packet.pure_syn():
                self.connections.remove(connection)
                return None, None
            return connection, direction
        return None, None

    def translate_destination(self, inbound, packet):
        for mapping in self.statics:
            if mapping.outside == packet.destination:
                return mapping.inside, packet.destination_port, None
        if packet.destination == inbound.address:
            for forward in self.forwards:
                if (forward.interface is inbound and forward.protocol == packet.protocol
                        and forward.outside_port == packet.destination_port):
                    return forward.inside_address, forward.inside_port, None
            for mapping in inbound.pat_mappings:
                if (mapping.protocol == packet.protocol
                        and mapping.outside_port == packet.destination_port):
                    return mapping.inside_address, mapping.inside_port, mapping
        return packet.destination, packet.destination_port, None

    def free_pat_port(self, interface):
        used = {mapping.outside_port for mapping in interface.pat_mappings}
        for forward in self.forwards:
            if forward.interface is interface:
                used.add(forward.outside_port)
        for port in range(PAT_FIRST_PORT, PAT_FIRST_PORT + interface.pat_size):
            if port not in used:
                return port
        return None

    def translate_source(self, outbound, packet):
        for mapping in self.statics:
            if mapping.inside == packet.source:
                return mapping.outside, packet.source_port, None
        for forward in self.forwards:
            if (forward.interface is outbound and forward.protocol == packet.protocol
                    and forward.inside_address == packet.source
                    and forward.inside_port == packet.source_port):
                return outbound.address, forward.outside_port, None
        if outbound.pat_size is None:
            return packet.source, packet.source_port, None
        for mapping in outbound.pat_mappings:
            if (mapping.protocol == packet.protocol
                    and mapping.inside_address == packet.source
                    and mapping.inside_port == packet.source_port):
                return outbound.address, mapping.outside_port, mapping
        port = self.free_pat_port(outbound)
        if port is None:
            return None
        mapping = PatMapping(packet.protocol, packet.source, packet.source_port, port, self.clock)
        outbound.pat_mappings.append(mapping)
        return outbound.address, port, mapping

    def process(self, packet):
        inbound = packet.interface
        if not inbound.up:
            return "down", "DROP down"
        if self.martian(packet.source, packet.destination):
            return "martian", "DROP martian"
        if inbound.rpf != "off":
            route = self.select_route(packet.source)
            if route is None or (inbound.rpf == "strict" and route.interface is not inbound):
                return "rpf", "DROP rpf"
        connection, direction = self.find_connection(packet)
        established = connection is not None
        if packet.protocol == "TCP" and not established and not packet.pure_syn():
            return "invalid", "DROP invalid"
        verdict = inbound.acls["in"].evaluate(packet.flow(), established)
        if verdict is not None:
            return "acl_in", verdict
        destination, destination_port, mapping = packet.destination, packet.destination_port, None
        if inbound.outside:
            destination, destination_port, mapping = self.translate_destination(inbound, packet)
        local = self.interface_with_address(destination)
        if local is not None:
            return "local", "LOCAL " + local.name
        if packet.ttl == 1:
            return "ttl", "DROP ttl"
        route = self.select_route(destination)
        if route is None:
            return "noroute", "DROP noroute"
        outbound = route.interface
        translated_flow = (
            packet.protocol, packet.source, packet.source_port, destination, destination_port,
        )
        verdict = outbound.acls["out"].evaluate(translated_flow, established)
        if verdict is not None:
            return "acl_out", verdict
        source, source_port = packet.source, packet.source_port
        if not inbound.outside and outbound.outside:
            translation = self.translate_source(outbound, packet)
            if translation is None:
                return "exhausted", "DROP exhausted"
            source, source_port, mapping = translation
        if mapping is not None:
            mapping.last_used = self.clock
        if connection is None:
            self.connection_count += 1
            reply = (packet.protocol, destination, destination_port, source, source_port)
            connection = Connection(
                self.connection_count, packet.flow(), reply, inbound, outbound
            )
            self.connections.append(connection)
            direction = "new"
        connection.record(direction, packet.flags, self.clock)
        outbound.tx += 1
        route.hits += 1
        hop = "direct" if route.next_hop is None else "via " + address_text(route.next_hop)
        parts = ["FORWARD", outbound.name, hop, f"ttl={packet.ttl - 1}"]
        if (destination, destination_port) != (packet.destination, packet.destination_port):
            parts.append("dnat=" + endpoint(destination, destination_port))
        if (source, source_port) != (packet.source, packet.source_port):
            parts.append("snat=" + endpoint(source, source_port))
        parts.extend((f"conn={connection.number}", direction))
        return "forwarded", " ".join(parts)

    def show(self, arguments):
        handlers = {
            "IFACES": self.show_interfaces,
            "ROUTES": self.show_routes,
            "ACL": self.show_acl,
            "NAT": self.show_nat,
            "CONNS": self.show_connections,
            "COUNTERS": self.show_counters,
        }
        handlers[arguments[0]]()

    def show_interfaces(self):
        self.emit("show", "ifaces", f"count={len(self.interfaces)}")
        for interface in self.sorted_interfaces():
            self.emit(interface.description())

    def show_routes(self):
        self.emit("show", "routes", f"count={len(self.routes)}")
        ordered = sorted(
            self.routes, key=lambda route: (route.network, route.length, route.metric)
        )
        for route in ordered:
            line = f"{route.notation()} hits={route.hits}"
            if not route.active():
                line += " inactive"
            self.emit(line)

    def show_acl(self):
        total = sum(
            len(access_list.rules)
            for interface in self.interfaces.values()
            for access_list in interface.acls.values()
        )
        self.emit("show", "acl", f"count={total}")
        for interface in self.sorted_interfaces():
            for direction in DIRECTIONS:
                access_list = interface.acls[direction]
                if not access_list.rules:
                    continue
                for rule in access_list.rules:
                    self.emit(rule.description(interface.name, direction))
                self.emit(
                    "acl", interface.name, direction, "default", "DENY",
                    f"hits={access_list.default_hits}",
                )

    def show_nat(self):
        mappings = []
        for interface in self.sorted_interfaces():
            ordered = sorted(interface.pat_mappings, key=lambda mapping: mapping.outside_port)
            mappings.extend((interface, mapping) for mapping in ordered)
        self.emit(
            "show", "nat", f"static={len(self.statics)}",
            f"forward={len(self.forwards)}", f"pat={len(mappings)}",
        )
        for mapping in sorted(self.statics, key=lambda mapping: mapping.inside):
            self.emit("static", address_text(mapping.inside), address_text(mapping.outside))
        forwards = sorted(
            self.forwards,
            key=lambda forward: (forward.interface.name, forward.outside_port, forward.protocol),
        )
        for forward in forwards:
            self.emit(
                "forward", forward.interface.name, forward.protocol, forward.outside_port,
                endpoint(forward.inside_address, forward.inside_port),
            )
        for interface, mapping in mappings:
            self.emit(
                "pat", interface.name, mapping.outside_port, mapping.protocol,
                endpoint(mapping.inside_address, mapping.inside_port),
                f"idle={self.clock - mapping.last_used}",
            )

    def show_connections(self):
        self.emit("show", "conns", f"count={len(self.connections)}")
        for connection in self.connections:
            self.emit(connection.description(self.clock))

    def show_counters(self):
        dropped = sum(self.counts[reason] for reason in DROP_REASONS)
        forwarded = self.counts["forwarded"]
        local = self.counts["local"]
        self.emit(
            "show", "counters", f"packets={forwarded + local + dropped}",
            f"forwarded={forwarded}", f"local={local}", f"dropped={dropped}",
            f"errors={self.errors}",
        )
        self.emit("drops", *(f"{reason}={self.counts[reason]}" for reason in DROP_REASONS))
        for interface in self.sorted_interfaces():
            self.emit(
                "iface", interface.name, f"rx={interface.rx}",
                f"tx={interface.tx}", f"drop={interface.drop}",
            )

    def clear(self, arguments):
        if arguments[0] == "COUNTERS":
            self.clear_counters()
        else:
            self.clear_connections()

    def clear_counters(self):
        self.counts = self.empty_counts()
        self.errors = 0
        for interface in self.interfaces.values():
            interface.rx = 0
            interface.tx = 0
            interface.drop = 0
            for access_list in interface.acls.values():
                access_list.clear_counters()
        for route in self.routes:
            route.hits = 0
        self.emit("ok", "clear", "counters")

    def clear_connections(self):
        removed_connections = len(self.connections)
        removed_mappings = 0
        for interface in self.interfaces.values():
            removed_mappings += len(interface.pat_mappings)
            interface.pat_mappings = []
        self.connections = []
        self.emit("ok", "clear", f"conns={removed_connections}", f"nat={removed_mappings}")

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "IFACE": self.add_interface,
            "UP": self.bring_up,
            "DOWN": self.bring_down,
            "ROUTE": self.add_route,
            "NOROUTE": self.remove_route,
            "ACL": self.add_rule,
            "NOACL": self.remove_rule,
            "NAT": self.nat,
            "RPF": self.set_rpf,
            "TIMEOUT": self.set_timeout,
            "TICK": self.tick,
            "LOOKUP": self.lookup,
            "PACKET": self.packet,
            "SHOW": self.show,
            "CLEAR": self.clear,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.errors += 1
            self.emit(f"error: {error}")


def main():
    router = Router()
    count = int(sys.stdin.readline())
    for _ in range(count):
        router.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(router.output) + "\n")


if __name__ == "__main__":
    main()
